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
    Mix.Task.run("loadconfig")
    config = Config.load()

    [
      Path.join(config.metadata_dir, "manifest.json"),
      "snakebridge.lock"
    ]
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
        "return_annotation" => info["return_annotation"],
        "return_type" => info["return_type"]
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
    Enum.each(config.libraries, fn library ->
      path = Path.join(config.generated_dir, "#{library.python_name}.ex")
      content = read_generated_file!(path)
      defs = parse_definitions!(content, path)

      missing_functions = missing_functions_for_library(manifest, library, defs)
      classes_for_library = classes_for_library(manifest, library)
      missing_classes = missing_classes_for_library(classes_for_library, defs)
      missing_class_members = missing_class_members_for_library(classes_for_library, defs)

      maybe_raise_missing!(path, missing_functions, missing_classes, missing_class_members)
    end)

    :ok
  end

  defp missing_functions_for_library(manifest, library, defs) do
    manifest
    |> functions_for_library(library)
    |> Enum.reject(fn info ->
      function_defined?(defs, info["module"], info["name"])
    end)
  end

  defp missing_classes_for_library(classes_for_library, defs) do
    Enum.reject(classes_for_library, fn info ->
      module = info["module"]
      Map.has_key?(defs, module)
    end)
  end

  defp missing_class_members_for_library(classes_for_library, defs) do
    classes_for_library
    |> Enum.filter(fn info -> Map.has_key?(defs, info["module"]) end)
    |> Enum.flat_map(&missing_members_for_class(&1, defs))
  end

  defp missing_members_for_class(info, defs) do
    module = info["module"]
    method_names = missing_method_names(info["methods"] || [], defs, module)
    attr_names = missing_attr_names(info["attributes"] || [], defs, module)

    Enum.map(method_names ++ attr_names, fn name ->
      {module, name}
    end)
  end

  defp missing_method_names(methods, defs, module) do
    methods
    |> Enum.map(&method_expected_name/1)
    |> Enum.reject(fn name ->
      name == "" or function_defined?(defs, module, name)
    end)
  end

  defp missing_attr_names(attrs, defs, module) do
    attrs
    |> Enum.map(&to_string/1)
    |> Enum.reject(fn name ->
      name == "" or function_defined?(defs, module, name)
    end)
  end

  defp maybe_raise_missing!(path, missing_functions, missing_classes, missing_class_members) do
    if missing_functions != [] or missing_classes != [] or missing_class_members != [] do
      raise SnakeBridge.CompileError, """
      Strict mode: Generated file #{path} is missing expected bindings.

      #{missing_functions_message(missing_functions)}\
      #{missing_classes_message(missing_classes)}\
      #{missing_class_members_message(missing_class_members)}
      Run `mix compile` locally to regenerate and commit the updated files.
      """
    end
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

  defp parse_definitions!(content, path) do
    case Code.string_to_quoted(content, file: path) do
      {:ok, ast} ->
        collect_definitions(ast)

      {:error, {line, error, token}} ->
        raise SnakeBridge.CompileError, """
        Strict mode: Cannot parse generated file #{path}: #{error} #{inspect(token)} on line #{line}
        """
    end
  end

  defp collect_definitions(ast) do
    initial = %{stack: [], defs: %{}}

    {_, acc} =
      Macro.traverse(ast, initial, &collect_pre/2, &collect_post/2)

    acc.defs
  end

  defp collect_pre({:defmodule, _, [{:__aliases__, _, parts}, _]} = node, acc) do
    segments = module_segments(parts, acc.stack)
    module_name = Enum.join(segments, ".")

    acc =
      acc
      |> Map.update!(:stack, &[segments | &1])
      |> Map.update(:defs, %{}, &Map.put_new(&1, module_name, MapSet.new()))

    {node, acc}
  end

  defp collect_pre({:def, _, [head | _]} = node, acc) do
    {node, track_def(acc, head)}
  end

  defp collect_pre(node, acc), do: {node, acc}

  defp track_def(acc, head) do
    case {def_name(head), List.first(acc.stack)} do
      {nil, _} ->
        acc

      {_, nil} ->
        acc

      {name, current_module} ->
        module_name = Enum.join(current_module, ".")

        Map.update(acc, :defs, %{}, fn defs ->
          Map.update(defs, module_name, MapSet.new([name]), &MapSet.put(&1, name))
        end)
    end
  end

  defp collect_post({:defmodule, _, _} = node, acc) do
    {_popped, rest} = List.pop_at(acc.stack, 0)
    {node, %{acc | stack: rest}}
  end

  defp collect_post(node, acc), do: {node, acc}

  defp module_segments(parts, []) do
    Enum.map(parts, &Atom.to_string/1)
  end

  defp module_segments(parts, [parent | _]) do
    parent ++ Enum.map(parts, &Atom.to_string/1)
  end

  defp def_name({:when, _, [inner | _]}), do: def_name(inner)
  defp def_name({name, _, _}) when is_atom(name), do: Atom.to_string(name)
  defp def_name(_), do: nil

  defp function_defined?(defs, module, name) when is_binary(module) and is_binary(name) do
    case Map.get(defs, module) do
      nil -> false
      set -> MapSet.member?(set, name)
    end
  end

  defp method_expected_name(%{"name" => "__init__"}), do: "new"
  defp method_expected_name(%{"name" => name}) when is_binary(name), do: name
  defp method_expected_name(%{name: "__init__"}), do: "new"
  defp method_expected_name(%{name: name}) when is_binary(name), do: name
  defp method_expected_name(_), do: ""

  defp missing_functions_message([]), do: ""

  defp missing_functions_message(missing) do
    formatted =
      missing
      |> Enum.map_join("\n", fn info ->
        module = info["module"] || "Unknown"
        name = info["name"] || "unknown"
        "  - #{module}.#{name}"
      end)

    """
    Missing functions:
    #{formatted}

    """
  end

  defp missing_classes_message([]), do: ""

  defp missing_classes_message(missing) do
    formatted =
      missing
      |> Enum.map_join("\n", fn info ->
        info["module"] || "Unknown"
      end)

    """
    Missing classes:
    #{formatted}

    """
  end

  defp missing_class_members_message([]), do: ""

  defp missing_class_members_message(missing) do
    formatted =
      missing
      |> Enum.map_join("\n", fn {module, name} ->
        "  - #{module}.#{name}"
      end)

    """
    Missing class members:
    #{formatted}

    """
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
