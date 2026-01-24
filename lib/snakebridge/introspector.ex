defmodule SnakeBridge.Introspector do
  @moduledoc """
  Introspects Python functions using the standalone introspection script.
  """

  alias SnakeBridge.IntrospectionError

  @type function_name :: atom() | String.t()

  @doc """
  Introspect an entire Python module to discover all public symbols.

  This is used when `generate: :all` is specified for a library.
  Unlike `introspect/2` which only inspects specific symbols, this
  function discovers all public functions, classes, and attributes.

  ## Options

  - `:submodules` - List of submodule names to also introspect (e.g., ["linalg", "fft"])
  - `:flat` - If true, use flat format (v2.0); otherwise use namespaced format (v2.1)

  ## Examples

      {:ok, result} = Introspector.introspect_module(library)
      {:ok, result} = Introspector.introspect_module(library, submodules: ["linalg"])

  """
  @spec introspect_module(SnakeBridge.Config.Library.t() | map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def introspect_module(library, opts \\ []) do
    start_time = System.monotonic_time()
    library_label = library_label(library)
    SnakeBridge.Telemetry.introspect_start(library_label, 0)
    python_name = library_python_name(library)
    config_json = introspection_config_json(library)

    args = build_module_args(python_name, config_json, library, opts)

    result =
      case run_script(args, runner_opts()) do
        {output, 0} -> parse_module_output(output, python_name)
        {output, _status} -> handle_python_error(output, python_name)
      end

    {symbols, classes} =
      case result do
        {:ok, data} -> count_module_symbols(data)
        _ -> {0, 0}
      end

    SnakeBridge.Telemetry.introspect_stop(
      start_time,
      library_label,
      symbols,
      classes,
      System.monotonic_time() - start_time
    )

    result
  end

  @doc """
  Fetch module docstrings without introspecting symbols.
  """
  @spec introspect_module_docs(SnakeBridge.Config.Library.t() | map(), [String.t()]) ::
          {:ok, list()} | {:error, term()}
  def introspect_module_docs(library, modules) when is_list(modules) do
    python_name = library_python_name(library)
    modules_json = Jason.encode!(Enum.map(modules, &to_string/1))
    config_json = introspection_config_json(library)

    case run_script(
           [
             script_path(),
             "--module",
             python_name,
             "--module-docs",
             modules_json,
             "--config",
             config_json
           ],
           runner_opts()
         ) do
      {output, 0} -> parse_output(output, python_name)
      {output, _status} -> handle_python_error(output, python_name)
    end
  end

  defp build_module_args(python_name, config_json, library, opts) do
    base = [script_path(), "--module", python_name, "--config", config_json]

    %{
      submodules: submodules,
      discover_submodules?: discover_submodules?,
      public_api?: public_api?,
      exports_mode?: exports_mode?,
      public_api_mode: public_api_mode,
      module_include: module_include,
      module_exclude: module_exclude,
      module_depth: module_depth
    } = resolve_module_settings(library, opts)

    base
    |> maybe_add_submodules(submodules)
    |> maybe_add_discover_submodules(discover_submodules?)
    |> maybe_add_public_api(public_api?)
    |> maybe_add_exports_mode(exports_mode?)
    |> maybe_add_public_api_mode(public_api_mode)
    |> maybe_add_module_include(module_include)
    |> maybe_add_module_exclude(module_exclude)
    |> maybe_add_module_depth(module_depth)
    |> maybe_add_flat(opts)
  end

  defp maybe_add_submodules(args, list) when is_list(list) and list != [] do
    args ++ ["--submodules", Enum.join(list, ",")]
  end

  defp maybe_add_submodules(args, _), do: args

  defp maybe_add_discover_submodules(args, true), do: args ++ ["--discover-submodules"]
  defp maybe_add_discover_submodules(args, _), do: args

  defp maybe_add_public_api(args, true), do: args ++ ["--public-api"]
  defp maybe_add_public_api(args, _), do: args

  defp maybe_add_exports_mode(args, true), do: args ++ ["--exports-mode"]
  defp maybe_add_exports_mode(args, _), do: args

  defp maybe_add_public_api_mode(args, nil), do: args

  defp maybe_add_public_api_mode(args, mode) when is_atom(mode) or is_binary(mode),
    do: args ++ ["--public-api-mode", to_string(mode)]

  defp maybe_add_module_include(args, []), do: args
  defp maybe_add_module_include(args, nil), do: args

  defp maybe_add_module_include(args, list),
    do: args ++ ["--module-include", Enum.join(list, ",")]

  defp maybe_add_module_exclude(args, []), do: args
  defp maybe_add_module_exclude(args, nil), do: args

  defp maybe_add_module_exclude(args, list),
    do: args ++ ["--module-exclude", Enum.join(list, ",")]

  defp maybe_add_module_depth(args, nil), do: args

  defp maybe_add_module_depth(args, depth) when is_integer(depth),
    do: args ++ ["--module-depth", Integer.to_string(depth)]

  defp maybe_add_flat(args, opts) do
    if Keyword.get(opts, :flat, false), do: args ++ ["--flat"], else: args
  end

  defp parse_module_output(output, package) do
    # Try direct parse first
    case Jason.decode(output) do
      {:ok, %{"error" => error}} ->
        {:error, normalize_error(error, package)}

      {:ok, result} when is_map(result) ->
        {:ok, result}

      {:error, _} ->
        # Output may contain warnings before JSON - try to extract JSON
        parse_extracted_json(output, package)
    end
  end

  # Extract a JSON object from output that may have warning lines before it
  defp extract_json_object(output) do
    # Find the first '{' and extract from there
    case :binary.match(output, "{") do
      {start, _} ->
        json_str = binary_part(output, start, byte_size(output) - start)
        {:ok, json_str}

      :nomatch ->
        :error
    end
  end

  defp parse_extracted_json(output, package) do
    case extract_json_object(output) do
      {:ok, json_str} ->
        decode_json_result(json_str, output, package)

      :error ->
        {:error, {:json_parse, output}}
    end
  end

  defp decode_json_result(json_str, output, package) do
    case Jason.decode(json_str) do
      {:ok, %{"error" => error}} -> {:error, normalize_error(error, package)}
      {:ok, result} when is_map(result) -> {:ok, result}
      {:error, _} -> {:error, {:json_parse, output}}
    end
  end

  defp count_module_symbols(%{"namespaces" => namespaces}) when is_map(namespaces) do
    Enum.reduce(namespaces, {0, 0}, fn {_ns, data}, {funcs, classes} ->
      ns_funcs = length(data["functions"] || [])
      ns_classes = length(data["classes"] || [])
      {funcs + ns_funcs, classes + ns_classes}
    end)
  end

  defp count_module_symbols(%{"functions" => funcs, "classes" => classes}) do
    {length(funcs || []), length(classes || [])}
  end

  defp count_module_symbols(_), do: {0, 0}

  @spec introspect(SnakeBridge.Config.Library.t() | map(), [function_name()]) ::
          {:ok, map()} | {:error, term()}
  def introspect(library, functions) when is_list(functions) do
    introspect(library, functions, nil)
  end

  @spec introspect(SnakeBridge.Config.Library.t() | map(), [function_name()], String.t() | nil) ::
          {:ok, map()} | {:error, term()}
  def introspect(library, functions, python_module) when is_list(functions) do
    case introspect_symbols(library, functions, python_module) do
      {:ok, infos} ->
        {:ok, group_symbols(infos)}

      {:error, _reason} = error ->
        error
    end
  end

  @spec introspect_symbols(
          SnakeBridge.Config.Library.t() | map(),
          [function_name()],
          String.t() | nil
        ) :: {:ok, list()} | {:error, term()}
  defp introspect_symbols(library, functions, python_module) when is_list(functions) do
    start_time = System.monotonic_time()
    library_label = library_label(library)
    SnakeBridge.Telemetry.introspect_start(library_label, length(functions))
    python_name = python_module || library_python_name(library)
    functions_json = Jason.encode!(Enum.map(functions, &to_string/1))

    config_json = introspection_config_json(library)

    result =
      case run_script(
             [
               script_path(),
               "--module",
               python_name,
               "--symbols",
               functions_json,
               "--config",
               config_json
             ],
             runner_opts()
           ) do
        {output, 0} -> parse_output(output, python_name)
        {output, _status} -> handle_python_error(output, python_name)
      end

    symbols =
      case result do
        {:ok, results} when is_list(results) -> length(results)
        _ -> 0
      end

    SnakeBridge.Telemetry.introspect_stop(
      start_time,
      library_label,
      symbols,
      0,
      System.monotonic_time() - start_time
    )

    result
  end

  @spec introspect_batch([
          {SnakeBridge.Config.Library.t() | map(), String.t(), list()}
        ]) ::
          list(
            {SnakeBridge.Config.Library.t() | map(), {:ok, list()} | {:error, term()}, String.t()}
          )
  def introspect_batch(libs_and_functions) when is_list(libs_and_functions) do
    nested_config = Application.get_env(:snakebridge, :introspector, [])
    default_timeout = Application.get_env(:snakebridge, :introspector_timeout, 30_000)

    default_concurrency =
      Application.get_env(:snakebridge, :introspector_max_concurrency, System.schedulers_online())

    max_concurrency = Keyword.get(nested_config, :max_concurrency, default_concurrency)
    timeout = Keyword.get(nested_config, :timeout, default_timeout)

    results =
      libs_and_functions
      |> Task.async_stream(
        fn {library, python_module, symbol_requests} ->
          names =
            symbol_requests
            |> Enum.map(&symbol_request_name/1)

          {library, introspect_symbols(library, names, python_module), python_module}
        end,
        max_concurrency: max_concurrency,
        timeout: timeout
      )
      |> Enum.to_list()

    libs_and_functions
    |> Enum.zip(results)
    |> Enum.map(fn
      {{_library, _python_module, _functions}, {:ok, result}} ->
        result

      {{library, python_module, functions}, {:exit, reason}} ->
        {library, {:error, batch_error(library, python_module, functions, reason)}, python_module}

      {{library, python_module, functions}, {:error, reason}} ->
        {library, {:error, batch_error(library, python_module, functions, reason)}, python_module}
    end)
  end

  defp symbol_request_name({name, _kind}) when is_binary(name), do: name
  defp symbol_request_name({name, _kind}) when is_atom(name), do: Atom.to_string(name)
  defp symbol_request_name(name) when is_binary(name), do: name
  defp symbol_request_name(name) when is_atom(name), do: Atom.to_string(name)
  defp symbol_request_name(other), do: to_string(other)

  @doc """
  Introspects a single attribute on a module to determine its type.
  """
  @spec introspect_attribute(String.t() | atom(), String.t() | atom(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def introspect_attribute(module_path, attr_name, opts \\ []) do
    runner_opts = Keyword.merge(runner_opts(), opts)

    case run_script(
           [
             script_path(),
             "--module",
             to_string(module_path),
             "--attribute",
             to_string(attr_name),
             "--config",
             introspection_config_json(%{python_name: to_string(module_path)})
           ],
           runner_opts
         ) do
      {output, 0} -> parse_attribute_output(output, to_string(module_path))
      {output, _status} -> handle_python_error(output, to_string(module_path))
    end
  end

  defp introspection_config_json(library) do
    library_config = normalize_library_config(library)

    config = %{
      "signature_sources" => signature_sources_config(library_config),
      "stub_search_paths" => stub_search_paths_config(library_config),
      "use_typeshed" => use_typeshed_config(library_config),
      "typeshed_path" => typeshed_path_config(library_config),
      "stubgen" => stubgen_config(library_config),
      "class_method_scope" => class_method_scope_config(library_config),
      "max_class_methods" => max_class_methods_config(library_config)
    }

    Jason.encode!(config)
  end

  defp normalize_library_config(library) when is_struct(library), do: Map.from_struct(library)
  defp normalize_library_config(library) when is_map(library), do: library
  defp normalize_library_config(_library), do: %{}

  defp signature_sources_config(library_config) do
    library_config
    |> Map.get(:signature_sources)
    |> default_signature_sources()
    |> Enum.map(&to_string/1)
  end

  defp stub_search_paths_config(library_config) do
    Application.get_env(:snakebridge, :stub_search_paths, [])
    |> Kernel.++(List.wrap(Map.get(library_config, :stub_search_paths)))
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
  end

  defp use_typeshed_config(library_config) do
    case Map.fetch(library_config, :use_typeshed) do
      {:ok, value} -> value
      :error -> Application.get_env(:snakebridge, :use_typeshed, false)
    end
  end

  defp typeshed_path_config(library_config) do
    Map.get(library_config, :typeshed_path) || Application.get_env(:snakebridge, :typeshed_path)
  end

  defp stubgen_config(library_config) do
    Application.get_env(:snakebridge, :stubgen, [])
    |> Keyword.merge(List.wrap(Map.get(library_config, :stubgen)))
    |> Enum.into(%{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp class_method_scope_config(library_config) do
    case library_or_global(library_config, :class_method_scope) do
      nil -> nil
      scope -> to_string(scope)
    end
  end

  defp max_class_methods_config(library_config),
    do: library_or_global(library_config, :max_class_methods)

  defp library_or_global(library_config, key) do
    case Map.fetch(library_config, key) do
      {:ok, value} -> value
      :error -> Application.get_env(:snakebridge, key)
    end
  end

  defp default_signature_sources(nil) do
    Application.get_env(:snakebridge, :signature_sources, [
      :runtime,
      :text_signature,
      :runtime_hints,
      :stub,
      :stubgen,
      :variadic
    ])
  end

  defp default_signature_sources(sources), do: List.wrap(sources)

  defp library_python_name(%{python_name: python_name}) when is_binary(python_name),
    do: python_name

  defp library_python_name(%{name: name}) when is_atom(name), do: Atom.to_string(name)
  defp library_python_name(name) when is_atom(name), do: Atom.to_string(name)
  defp library_python_name(name) when is_binary(name), do: name
  defp library_python_name(_), do: "unknown"

  defp script_path do
    Path.join(to_string(:code.priv_dir(:snakebridge)), "python/introspect.py")
  end

  defp library_label(%{name: name}) when is_atom(name), do: name
  defp library_label(name) when is_atom(name), do: name
  defp library_label(_), do: :unknown

  defp resolve_module_settings(library, opts) do
    mode = resolve_module_mode(library, opts)

    {submodules, discover_submodules?, public_api?, exports_mode?, public_api_mode} =
      module_mode_flags(mode)

    %{
      submodules: submodules,
      discover_submodules?: discover_submodules?,
      public_api?: public_api?,
      exports_mode?: exports_mode?,
      public_api_mode: public_api_mode,
      module_include: resolve_module_list_option(library, opts, :module_include),
      module_exclude: resolve_module_list_option(library, opts, :module_exclude),
      module_depth: resolve_module_depth_option(library, opts)
    }
  end

  defp resolve_module_list_option(library, opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> normalize_module_list(value)
      :error when is_map(library) -> normalize_module_list(Map.get(library, key))
      :error -> nil
    end
  end

  defp resolve_module_depth_option(library, opts) do
    case Keyword.fetch(opts, :module_depth) do
      {:ok, depth} -> normalize_module_depth(depth)
      :error when is_map(library) -> normalize_module_depth(Map.get(library, :module_depth))
      :error -> nil
    end
  end

  defp resolve_module_mode(library, opts) do
    case Keyword.fetch(opts, :submodules) do
      {:ok, list} when is_list(list) ->
        {:only, normalize_module_list(list)}

      {:ok, true} ->
        resolve_submodules_true(library, opts)

      {:ok, false} ->
        :root

      :error ->
        resolve_module_mode_from_config(library, opts)
    end
  end

  defp resolve_submodules_true(library, opts) do
    public_api? = Keyword.get(opts, :public_api, library_public_api(library))
    if public_api?, do: :public, else: :all
  end

  defp resolve_module_mode_from_config(library, opts) do
    case Keyword.get(opts, :module_mode) || library_module_mode(library) do
      nil when is_map(library) -> legacy_mode_from_library(library)
      nil -> :root
      mode -> normalize_module_mode(mode)
    end
  end

  defp legacy_mode_from_library(library) do
    case Map.get(library, :submodules) do
      true -> if(library_public_api(library), do: :public, else: :all)
      list when is_list(list) -> {:only, normalize_module_list(list)}
      _ -> :root
    end
  end

  defp module_mode_flags({:only, list}) when is_list(list),
    do: {list, false, false, false, nil}

  defp module_mode_flags(:exports), do: {nil, false, false, true, nil}
  defp module_mode_flags(:explicit), do: {nil, true, true, false, :explicit_all}
  defp module_mode_flags(:public), do: {nil, true, true, false, nil}
  defp module_mode_flags(:docs), do: {nil, false, false, false, nil}
  defp module_mode_flags(:all), do: {nil, true, false, false, nil}
  defp module_mode_flags(:root), do: {nil, false, false, false, nil}

  defp normalize_module_mode(:light), do: :root
  defp normalize_module_mode(:top), do: :root
  defp normalize_module_mode(:root), do: :root
  defp normalize_module_mode(:api), do: :exports
  defp normalize_module_mode(:exports), do: :exports
  defp normalize_module_mode(:explicit), do: :explicit
  defp normalize_module_mode(:manifest), do: :docs
  defp normalize_module_mode(:docs), do: :docs
  defp normalize_module_mode(:standard), do: :public
  defp normalize_module_mode(:public), do: :public
  defp normalize_module_mode(:full), do: :all
  defp normalize_module_mode(:nuclear), do: :all
  defp normalize_module_mode(:all), do: :all

  defp normalize_module_mode({:only, list}) when is_list(list),
    do: {:only, normalize_module_list(list)}

  defp normalize_module_mode(_), do: :root

  defp normalize_module_list(nil), do: []
  defp normalize_module_list(list) when is_list(list), do: Enum.map(list, &to_string/1)
  defp normalize_module_list(value) when is_binary(value), do: [value]
  defp normalize_module_list(_), do: []

  defp normalize_module_depth(nil), do: nil
  defp normalize_module_depth(value) when is_integer(value) and value > 0, do: value
  defp normalize_module_depth(_), do: nil

  defp library_public_api(library) when is_map(library), do: Map.get(library, :public_api, false)
  defp library_public_api(_), do: false

  defp library_module_mode(library) when is_map(library), do: Map.get(library, :module_mode)
  defp library_module_mode(_), do: nil

  defp runner_opts do
    config = Application.get_env(:snakebridge, :introspector, [])
    Keyword.take(config, [:timeout, :env, :cd])
  end

  defp parse_output(output, package) do
    case Jason.decode(output) do
      {:ok, results} when is_list(results) -> {:ok, results}
      {:ok, %{"error" => error}} -> {:error, normalize_error(error, package)}
      {:error, _} -> {:error, {:json_parse, output}}
    end
  end

  defp parse_attribute_output(output, package) do
    case Jason.decode(output) do
      {:ok, %{"error" => error}} -> {:error, normalize_error(error, package)}
      {:ok, result} when is_map(result) -> {:ok, result}
      {:error, _} -> {:error, {:json_parse, output}}
    end
  end

  defp normalize_error(error, package) when is_binary(error) do
    IntrospectionError.from_python_output(error, package)
  end

  defp normalize_error(error, _package), do: error

  defp group_symbols(infos) do
    infos
    |> Enum.reduce(%{"functions" => [], "classes" => [], "attributes" => []}, fn info, acc ->
      case info["type"] || info[:type] do
        "class" ->
          Map.update!(acc, "classes", &[info | &1])

        "attribute" ->
          Map.update!(acc, "attributes", &[info | &1])

        _ ->
          Map.update!(acc, "functions", &[info | &1])
      end
    end)
    |> Map.update!("functions", &Enum.reverse/1)
    |> Map.update!("classes", &Enum.reverse/1)
    |> Map.update!("attributes", &Enum.reverse/1)
  end

  defp run_script(args, opts) do
    {timeout, opts} = Keyword.pop(opts, :timeout)
    cmd_opts = [stderr_to_stdout: true]
    env = build_env(opts)
    cmd_opts = if env == [], do: cmd_opts, else: Keyword.put(cmd_opts, :env, env)
    cmd_opts = maybe_put_opt(cmd_opts, :cd, opts)
    run = fn -> System.cmd(python_executable(), args, cmd_opts) end

    if is_integer(timeout) do
      task = Task.async(run)

      case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> result
        nil -> {"Command timed out after #{timeout}ms", 124}
      end
    else
      run.()
    end
  end

  defp python_executable do
    Application.get_env(:snakebridge, :python_executable) ||
      resolve_snakepit_executable() ||
      System.find_executable("python3") ||
      "python3"
  end

  defp resolve_snakepit_executable do
    if Code.ensure_loaded?(Snakepit.PythonRuntime) and
         function_exported?(Snakepit.PythonRuntime, :resolve_executable, 0) do
      case Snakepit.PythonRuntime.resolve_executable() do
        {:ok, python, _meta} -> python
        _ -> nil
      end
    else
      nil
    end
  end

  defp build_env(opts) do
    runtime_env =
      if Code.ensure_loaded?(Snakepit.PythonRuntime) and
           function_exported?(Snakepit.PythonRuntime, :runtime_env, 0) do
        Snakepit.PythonRuntime.runtime_env()
      else
        []
      end

    extra_env =
      if Code.ensure_loaded?(Snakepit.PythonRuntime) and
           function_exported?(Snakepit.PythonRuntime, :config, 0) do
        Snakepit.PythonRuntime.config() |> Map.get(:extra_env, %{}) |> Enum.to_list()
      else
        []
      end

    user_env =
      opts
      |> Keyword.get(:env, %{})
      |> Enum.to_list()

    runtime_env
    |> Kernel.++(extra_env)
    |> Kernel.++(user_env)
    |> maybe_add_pythonpath()
  end

  defp maybe_add_pythonpath(env) do
    if Enum.any?(env, fn {key, _value} -> String.downcase(key) == "pythonpath" end) do
      env
    else
      case default_pythonpath() do
        nil -> env
        pythonpath -> env ++ [{"PYTHONPATH", pythonpath}]
      end
    end
  end

  defp default_pythonpath do
    path_sep = if match?({:win32, _}, :os.type()), do: ";", else: ":"
    project_priv = project_priv_python()
    snakebridge_priv = snakebridge_priv_python()

    paths =
      [System.get_env("PYTHONPATH"), project_priv, snakebridge_priv]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()

    if paths == [] do
      nil
    else
      Enum.join(paths, path_sep)
    end
  end

  defp project_priv_python do
    path = Path.join(File.cwd!(), "priv/python")
    if File.dir?(path), do: path, else: nil
  end

  defp snakebridge_priv_python do
    case :code.priv_dir(:snakebridge) do
      {:error, _} -> nil
      priv_dir -> Path.join(to_string(priv_dir), "python")
    end
  end

  defp maybe_put_opt(cmd_opts, key, opts) do
    case Keyword.get(opts, key) do
      nil -> cmd_opts
      value -> Keyword.put(cmd_opts, key, value)
    end
  end

  defp handle_python_error(output, package) do
    {:error, IntrospectionError.from_python_output(output, package)}
  end

  defp batch_error(library, python_module, functions, reason) do
    %{
      type: :introspection_batch_failed,
      library: library_label(library),
      python_module: python_module,
      functions: functions,
      reason: reason
    }
  end
end
