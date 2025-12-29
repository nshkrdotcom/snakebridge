defmodule Mix.Tasks.Compile.Snakebridge do
  @moduledoc """
  Mix compiler that runs the SnakeBridge pre-pass (scan → introspect → generate).
  """

  use Mix.Task.Compiler

  alias SnakeBridge.{
    Config,
    Generator,
    HelperGenerator,
    Helpers,
    Introspector,
    Lock,
    Manifest,
    PythonEnv,
    Scanner,
    Telemetry
  }

  @impl Mix.Task.Compiler
  def run(_args) do
    Mix.Task.run("loadconfig")

    if skip_generation?() do
      {:ok, []}
    else
      config = Config.load()
      run_with_config(config)
    end
  end

  defp run_with_config(%{libraries: []}), do: {:ok, []}

  defp run_with_config(config) do
    if strict_mode?(config) do
      run_strict(config)
    else
      PythonEnv.ensure!(config)
      run_normal(config)
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

  defp strict_mode?(config) do
    System.get_env("SNAKEBRIDGE_STRICT") == "1" || config.strict == true
  end

  defp run_strict(config) do
    manifest = Manifest.load(config)
    detected = scanner_module().scan_project(config)
    missing = Manifest.missing(manifest, detected)

    if missing != [] do
      formatted = format_missing(missing)

      raise SnakeBridge.CompileError, """
      Strict mode: #{length(missing)} symbol(s) not in manifest.

      Missing:
      #{formatted}

      To fix:
        1. Run `mix snakebridge.setup` locally
        2. Run `mix compile` to generate bindings
        3. Commit the updated manifest and generated files
        4. Re-run CI

      Set SNAKEBRIDGE_STRICT=0 to disable strict mode.
      """
    end

    verify_generated_files_exist!(config)
    verify_symbols_present!(config, manifest)

    {:ok, []}
  end

  defp run_normal(config) do
    start_time = System.monotonic_time()
    libraries = Enum.map(config.libraries, & &1.name)
    Telemetry.compile_start(libraries, false)

    try do
      detected = scanner_module().scan_project(config)
      manifest = Manifest.load(config)
      missing = Manifest.missing(manifest, detected)
      targets = build_targets(missing, config, manifest)

      updated_manifest =
        if targets != [] do
          update_manifest(manifest, targets)
        else
          manifest
        end

      Manifest.save(config, updated_manifest)
      generate_from_manifest(config, updated_manifest)
      generate_helper_wrappers(config)
      Lock.update(config)

      symbol_count = count_symbols(updated_manifest)
      file_count = length(config.libraries)
      Telemetry.compile_stop(start_time, symbol_count, file_count, libraries, :normal)
      {:ok, []}
    rescue
      e ->
        Telemetry.compile_exception(start_time, e, __STACKTRACE__)
        reraise e, __STACKTRACE__
    end
  end

  @spec verify_generated_files_exist!(Config.t()) :: :ok
  def verify_generated_files_exist!(config) do
    Enum.each(config.libraries, fn library ->
      path = Path.join(config.generated_dir, "#{library.python_name}.ex")

      unless File.exists?(path) do
        raise SnakeBridge.CompileError, """
        Strict mode: Generated file missing: #{path}

        Run `mix compile` locally and commit the generated files.
        """
      end
    end)

    :ok
  end

  @spec verify_symbols_present!(Config.t(), map()) :: :ok
  def verify_symbols_present!(config, manifest) do
    symbols = Map.get(manifest, "symbols", %{})

    Enum.each(config.libraries, fn library ->
      path = Path.join(config.generated_dir, "#{library.python_name}.ex")
      content = read_generated_file!(path)
      expected_functions = expected_functions_for_library(symbols, library)

      missing_in_file =
        Enum.reject(expected_functions, fn name ->
          String.contains?(content, "def #{name}(")
        end)

      if missing_in_file != [] do
        raise SnakeBridge.CompileError, """
        Strict mode: Generated file #{path} is missing expected functions:
        #{Enum.map_join(missing_in_file, "\n", &"  - #{&1}")}

        Run `mix compile` locally to regenerate and commit the updated files.
        """
      end
    end)

    :ok
  end

  defp required_arity(params) do
    params
    |> Enum.filter(&(&1["kind"] in ["POSITIONAL_ONLY", "POSITIONAL_OR_KEYWORD"]))
    |> Enum.reject(&Map.has_key?(&1, "default"))
    |> length()
  end

  defp format_missing(missing) do
    missing
    |> Enum.sort()
    |> Enum.map_join("\n", fn {mod, fun, arity} ->
      module = Module.split(mod) |> Enum.join(".")
      "  - #{module}.#{fun}/#{arity}"
    end)
  end

  defp scanner_module do
    Application.get_env(:snakebridge, :scanner, Scanner)
  end

  defp read_generated_file!(path) do
    case File.read(path) do
      {:ok, content} ->
        content

      {:error, reason} ->
        raise SnakeBridge.CompileError, """
        Strict mode: Cannot read generated file #{path}: #{inspect(reason)}
        """
    end
  end

  defp expected_functions_for_library(symbols, library) do
    symbols
    |> Map.values()
    |> Enum.filter(fn info ->
      python_module = info["python_module"] || ""
      String.starts_with?(python_module, library.python_name)
    end)
    |> Enum.map(& &1["name"])
  end

  defp count_symbols(manifest) do
    symbols = Map.get(manifest, "symbols", %{}) |> map_size()
    classes = Map.get(manifest, "classes", %{}) |> map_size()
    symbols + classes
  end

  defp generate_helper_wrappers(config) do
    if Helpers.enabled?(config) do
      case Helpers.discover(config) do
        {:ok, helpers} ->
          HelperGenerator.generate_helpers(helpers, config)

        {:error, %SnakeBridge.HelperRegistryError{} = error} ->
          Mix.shell().error(Exception.message(error))
          :ok

        {:error, reason} ->
          Mix.shell().error("Helper registry failed: #{inspect(reason)}")
          :ok
      end
    else
      :ok
    end
  end
end
