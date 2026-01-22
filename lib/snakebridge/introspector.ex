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
    {submodules, discover_submodules?} = resolve_submodules(library, opts)

    base
    |> maybe_add_submodules(submodules)
    |> maybe_add_discover_submodules(discover_submodules?)
    |> maybe_add_flat(opts)
  end

  defp maybe_add_submodules(args, list) when is_list(list) and list != [] do
    args ++ ["--submodules", Enum.join(list, ",")]
  end

  defp maybe_add_submodules(args, _), do: args

  defp maybe_add_discover_submodules(args, true), do: args ++ ["--discover-submodules"]
  defp maybe_add_discover_submodules(args, _), do: args

  defp maybe_add_flat(args, opts) do
    if Keyword.get(opts, :flat, false), do: args ++ ["--flat"], else: args
  end

  defp parse_module_output(output, package) do
    case Jason.decode(output) do
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
          {SnakeBridge.Config.Library.t() | map(), String.t(), [function_name()]}
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
        fn {library, python_module, functions} ->
          {library, introspect_symbols(library, functions, python_module), python_module}
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
    library_config =
      cond do
        is_struct(library) -> Map.from_struct(library)
        is_map(library) -> library
        true -> %{}
      end

    signature_sources =
      library_config
      |> Map.get(:signature_sources)
      |> default_signature_sources()
      |> Enum.map(&to_string/1)

    stub_search_paths =
      Application.get_env(:snakebridge, :stub_search_paths, [])
      |> Kernel.++(List.wrap(Map.get(library_config, :stub_search_paths) || []))
      |> Enum.map(&to_string/1)
      |> Enum.uniq()

    use_typeshed =
      case Map.get(library_config, :use_typeshed) do
        nil -> Application.get_env(:snakebridge, :use_typeshed, false)
        value -> value
      end

    typeshed_path =
      Map.get(library_config, :typeshed_path) ||
        Application.get_env(:snakebridge, :typeshed_path)

    stubgen_config =
      Application.get_env(:snakebridge, :stubgen, [])
      |> Keyword.merge(List.wrap(Map.get(library_config, :stubgen) || []))
      |> Enum.into(%{}, fn {key, value} -> {to_string(key), value} end)

    config = %{
      "signature_sources" => signature_sources,
      "stub_search_paths" => stub_search_paths,
      "use_typeshed" => use_typeshed,
      "typeshed_path" => typeshed_path,
      "stubgen" => stubgen_config
    }

    Jason.encode!(config)
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

  defp resolve_submodules(library, opts) do
    submodules_opt = Keyword.get(opts, :submodules)

    library_submodules =
      if is_map(library) do
        Map.get(library, :submodules)
      else
        nil
      end

    case submodules_opt do
      list when is_list(list) ->
        {list, false}

      _ ->
        case library_submodules do
          true -> {nil, true}
          list when is_list(list) -> {list, false}
          _ -> {nil, false}
        end
    end
  end

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
