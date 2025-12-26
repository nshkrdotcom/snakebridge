defmodule Mix.Tasks.Compile.Snakebridge do
  @moduledoc """
  Mix compiler that runs the SnakeBridge pre-pass (scan → introspect → generate).
  """

  use Mix.Task.Compiler

  alias SnakeBridge.{Config, Generator, Introspector, Lock, Manifest, Scanner}

  @impl Mix.Task.Compiler
  def run(_args) do
    Mix.Task.run("loadconfig")

    if skip_generation?() do
      {:ok, []}
    else
      config = Config.load()

      if config.libraries == [] do
        {:ok, []}
      else
        run_with_config(config)
      end
    end
  end

  @impl Mix.Task.Compiler
  def manifests do
    []
  end

  defp skip_generation? do
    case System.get_env("SNAKEBRIDGE_SKIP") do
      nil -> false
      value -> value in ["1", "true", "TRUE", "yes", "YES"]
    end
  end

  defp update_manifest(manifest, targets) do
    targets
    |> Introspector.introspect_batch()
    |> Enum.reduce(manifest, fn {library, result, python_module}, acc ->
      case result do
        {:ok, infos} ->
          {symbol_entries, class_entries} =
            build_manifest_entries(library, python_module, infos)

          acc
          |> Manifest.put_symbols(symbol_entries)
          |> Manifest.put_classes(class_entries)

        {:error, _reason} ->
          acc
      end
    end)
  end

  defp build_targets(missing, config, manifest) do
    initial =
      Enum.reduce(missing, %{}, fn entry, acc ->
        accumulate_missing_target(entry, acc, config)
      end)

    with_includes =
      Enum.reduce(config.libraries, initial, fn library, acc ->
        includes =
          library.include
          |> Enum.reject(&function_or_class_present?(manifest, library, &1))

        accumulate_includes(includes, library, acc)
      end)

    with_includes
    |> Enum.map(fn {{library, python_module}, functions} ->
      filtered = Enum.reject(functions, &(&1 in library.exclude))
      {library, python_module, Enum.uniq(filtered)}
    end)
    |> Enum.reject(fn {_library, _python_module, functions} -> functions == [] end)
  end

  defp accumulate_missing_target({module, function, _arity}, acc, config) do
    case library_for_module(config, module) do
      nil ->
        acc

      library ->
        python_module = python_module_for_elixir(library, module)
        add_target(acc, library, python_module, function)
    end
  end

  defp accumulate_includes([], _library, acc), do: acc

  defp accumulate_includes(includes, library, acc) do
    key = {library, library.python_name}
    Map.update(acc, key, includes, fn funcs -> includes ++ funcs end)
  end

  defp add_target(acc, library, python_module, function) do
    key = {library, python_module}
    Map.update(acc, key, [function], fn funcs -> [function | funcs] end)
  end

  defp library_for_module(config, module) do
    module_parts = Module.split(module)

    Enum.find(config.libraries, fn library ->
      library_parts = Module.split(library.module_name)
      Enum.take(module_parts, length(library_parts)) == library_parts
    end)
  end

  defp build_manifest_entries(library, python_module, infos) do
    Enum.reduce(infos, {[], []}, fn info, {symbols, classes} ->
      cond do
        info["error"] ->
          {symbols, classes}

        info["type"] == "class" ->
          class_entries = class_entries_for(library, python_module, info)
          {symbols, class_entries ++ classes}

        true ->
          symbol_entry = symbol_entry_for(library, python_module, info)
          {[symbol_entry | symbols], classes}
      end
    end)
  end

  defp symbol_entry_for(library, python_module, info) do
    module = module_for_python(library, python_module)
    function = info["name"]
    arity = required_arity(info["parameters"] || [])

    key = Manifest.symbol_key({module, String.to_atom(function), arity})

    {
      key,
      %{
        "module" => Module.split(module) |> Enum.join("."),
        "function" => function,
        "name" => function,
        "python_module" => python_module,
        "parameters" => info["parameters"] || [],
        "docstring" => info["docstring"] || "",
        "return_annotation" => info["return_annotation"]
      }
    }
  end

  defp class_entries_for(library, python_module, info) do
    class_name = info["name"] || info["class"] || "Class"
    class_python_module = info["python_module"] || python_module || library.python_name
    class_module = class_module_for(library, class_python_module, class_name)
    key = Manifest.class_key(class_module)

    [
      {
        key,
        %{
          "module" => Module.split(class_module) |> Enum.join("."),
          "class" => class_name,
          "python_module" => class_python_module,
          "docstring" => info["docstring"] || "",
          "methods" => info["methods"] || [],
          "attributes" => info["attributes"] || []
        }
      }
    ]
  end

  defp class_module_for(library, python_module, class_name) do
    python_parts = String.split(python_module, ".")
    library_parts = String.split(library.python_name, ".")
    extra_parts = Enum.drop(python_parts, length(library_parts))
    extra_parts = drop_class_suffix(extra_parts, class_name)

    library.module_name
    |> Module.split()
    |> Kernel.++(Enum.map(extra_parts, &Macro.camelize/1))
    |> Kernel.++([class_name])
    |> Module.concat()
  end

  defp drop_class_suffix(parts, class_name) when is_list(parts) and is_binary(class_name) do
    class_suffix = Macro.underscore(class_name)

    case List.last(parts) do
      ^class_suffix -> Enum.drop(parts, -1)
      _ -> parts
    end
  end

  defp drop_class_suffix(parts, _class_name), do: parts

  defp module_for_python(library, python_module) do
    python_parts = String.split(python_module, ".")
    library_parts = String.split(library.python_name, ".")
    extra_parts = Enum.drop(python_parts, length(library_parts))

    library.module_name
    |> Module.split()
    |> Kernel.++(Enum.map(extra_parts, &Macro.camelize/1))
    |> Module.concat()
  end

  defp python_module_for_elixir(library, module) do
    module_parts = Module.split(module)
    library_parts = Module.split(library.module_name)
    extra_parts = Enum.drop(module_parts, length(library_parts))

    case Enum.map(extra_parts, &Macro.underscore/1) do
      [] -> library.python_name
      parts -> library.python_name <> "." <> Enum.join(parts, ".")
    end
  end

  defp function_or_class_present?(manifest, library, name) do
    module_prefix = Module.split(library.module_name) |> Enum.join(".")
    function_prefix = "#{module_prefix}.#{name}/"

    function_exists? =
      manifest
      |> Map.get("symbols", %{})
      |> Map.keys()
      |> Enum.any?(&String.starts_with?(&1, function_prefix))

    class_exists? =
      manifest
      |> Map.get("classes", %{})
      |> Map.values()
      |> Enum.any?(fn info ->
        info["class"] == name or String.ends_with?(info["module"] || "", ".#{name}")
      end)

    function_exists? or class_exists?
  end

  defp generate_from_manifest(config, manifest) do
    Enum.each(config.libraries, fn library ->
      functions = functions_for_library(manifest, library)
      classes = classes_for_library(manifest, library)
      Generator.generate_library(library, functions, classes, config)
    end)
  end

  defp functions_for_library(manifest, library) do
    Map.get(manifest, "symbols", %{})
    |> Map.values()
    |> Enum.filter(fn info ->
      python_module = info["python_module"] || ""
      String.starts_with?(python_module, library.python_name)
    end)
  end

  defp classes_for_library(manifest, library) do
    Map.get(manifest, "classes", %{})
    |> Map.values()
    |> Enum.filter(fn info ->
      python_module = info["python_module"] || ""
      String.starts_with?(python_module, library.python_name)
    end)
  end

  defp run_with_config(config) do
    detected = Scanner.scan_project(config)
    manifest = Manifest.load(config)
    missing = Manifest.missing(manifest, detected)
    targets = build_targets(missing, config, manifest)

    if config.strict and targets != [] do
      {:error, [diagnostic("Strict mode: generation needed for: #{format_targets(targets)}")]}
    else
      updated_manifest =
        if targets != [] do
          update_manifest(manifest, targets)
        else
          manifest
        end

      Manifest.save(config, updated_manifest)
      generate_from_manifest(config, updated_manifest)
      Lock.update(config)
      {:ok, []}
    end
  end

  defp required_arity(params) do
    params
    |> Enum.filter(&(&1["kind"] in ["POSITIONAL_ONLY", "POSITIONAL_OR_KEYWORD"]))
    |> Enum.reject(&Map.has_key?(&1, "default"))
    |> length()
  end

  defp diagnostic(message) do
    %Mix.Task.Compiler.Diagnostic{
      compiler_name: "snakebridge",
      details: nil,
      file: "mix.exs",
      message: message,
      position: 1,
      severity: :error
    }
  end

  defp format_targets(targets) do
    targets
    |> Enum.flat_map(fn {library, python_module, functions} ->
      module = module_for_python(library, python_module)
      Enum.map(functions, fn name -> "#{module}.#{name}" end)
    end)
    |> Enum.join(", ")
  end
end
