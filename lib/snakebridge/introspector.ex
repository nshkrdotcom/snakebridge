defmodule SnakeBridge.Introspector do
  @moduledoc """
  Introspects Python functions using the standalone introspection script.
  """

  alias SnakeBridge.IntrospectionError

  @type function_name :: atom() | String.t()

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

    result =
      case run_script(
             [
               script_path(),
               "--module",
               python_name,
               "--symbols",
               functions_json
             ],
             runner_opts()
           ) do
        {output, 0} -> parse_output(output)
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
             to_string(attr_name)
           ],
           runner_opts
         ) do
      {output, 0} -> parse_attribute_output(output)
      {output, _status} -> handle_python_error(output, to_string(module_path))
    end
  end

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

  defp runner_opts do
    config = Application.get_env(:snakebridge, :introspector, [])
    Keyword.take(config, [:timeout, :env, :cd])
  end

  defp parse_output(output) do
    case Jason.decode(output) do
      {:ok, results} when is_list(results) -> {:ok, results}
      {:ok, %{"error" => error}} -> {:error, error}
      {:error, _} -> {:error, {:json_parse, output}}
    end
  end

  defp parse_attribute_output(output) do
    case Jason.decode(output) do
      {:ok, %{"error" => error}} -> {:error, error}
      {:ok, result} when is_map(result) -> {:ok, result}
      {:error, _} -> {:error, {:json_parse, output}}
    end
  end

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

    runtime_env ++ extra_env ++ user_env
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
