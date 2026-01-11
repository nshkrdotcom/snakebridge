defmodule SnakeBridge.RealPythonCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Snakepit.Adapters.GRPCPython

  @pool_ready_timeout 30_000
  @pool_queue_timeout 20_000
  @worker_ready_poll_ms 100
  @configured_key {__MODULE__, :real_python_configured}
  @python_key {__MODULE__, :real_python_python}
  @active_count_key {__MODULE__, :real_python_active}
  @original_env_key {__MODULE__, :real_python_original_env}
  @snakepit_env_keys [
    :pooling_enabled,
    :adapter_module,
    :pool_config,
    :pools,
    :heartbeat,
    :python_executable,
    :pool_queue_timeout
  ]

  using do
    quote do
      use ExUnit.Case, async: false
      import SnakeBridge.RealPythonCase, only: [setup_real_python: 1, ensure_pool_available: 1]
      setup_all :setup_real_python
      setup :ensure_pool_available
    end
  end

  def ensure_pool_available(_context) do
    if pool_has_available_workers?() do
      :ok
    else
      restart_snakepit_pool()
    end
  end

  def setup_real_python(context) do
    ensure_original_env()
    increment_active_count()

    on_exit(fn -> teardown_real_python() end)

    case ensure_real_python() do
      :ok -> context
      {:skip, reason} -> {:skip, reason}
    end
  end

  defp ensure_real_python do
    with {:ok, python} <- resolve_python(),
         {:ok, python} <- ensure_python_deps(python) do
      store_python_path(python)
      ensure_snakepit_pool(python)
    end
  end

  defp resolve_python do
    python =
      System.get_env("SNAKEBRIDGE_TEST_PYTHON") ||
        Application.get_env(:snakepit, :python_executable) ||
        System.get_env("SNAKEPIT_PYTHON") ||
        GRPCPython.executable_path() ||
        System.find_executable("python3") ||
        System.find_executable("python")

    if is_binary(python) do
      {:ok, python}
    else
      {:skip, "python3 not available"}
    end
  end

  defp resolve_python_with_cache do
    case stored_python_path() do
      nil -> resolve_python()
      python -> {:ok, python}
    end
  end

  defp ensure_python_deps(python) do
    env = [{"PYTHONPATH", build_pythonpath()}]

    case check_python_deps(python, env) do
      :ok ->
        {:ok, python}

      {:error, output} ->
        handle_missing_python_deps(python, env, output)
    end
  end

  defp check_python_deps(python, env) do
    case System.cmd(python, ["-c", "import grpc, google.protobuf, snakebridge_adapter"],
           env: env,
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {output, _status} -> {:error, output}
    end
  end

  defp handle_missing_python_deps(python, _env, output) do
    if python_override?() do
      {:skip,
       "python deps missing in override (grpc/protobuf/snakebridge_adapter): #{String.trim(output)}"}
    else
      fetch_snakepit_requirements(python, output)
    end
  end

  defp fetch_snakepit_requirements(python, output) do
    case ensure_snakepit_requirements() do
      :ok ->
        refreshed_python = GRPCPython.executable_path() || python
        resolve_missing_deps(refreshed_python, output)

      {:skip, reason} ->
        {:skip, reason}
    end
  end

  defp resolve_missing_deps(nil, output), do: {:skip, missing_deps_message(output)}

  defp resolve_missing_deps(python, output) do
    env = [{"PYTHONPATH", build_pythonpath()}]

    case check_python_deps(python, env) do
      :ok -> {:ok, python}
      {:error, retry_output} -> {:skip, missing_deps_message(retry_output || output)}
    end
  end

  defp missing_deps_message(output) do
    "python deps missing (grpc/protobuf/snakebridge_adapter): #{String.trim(output)}"
  end

  defp ensure_snakepit_pool(python) do
    configure_snakepit(python)

    if started_app?(:snakepit) do
      if Process.whereis(Snakepit.Pool) == nil or not snakepit_configured?() do
        clear_snakepit_configured()
        Application.stop(:snakepit)
      end
    end

    case Application.ensure_all_started(:snakepit) do
      {:ok, _} ->
        case await_pool_ready() do
          :ok ->
            mark_snakepit_configured()
            :ok

          {:skip, _reason} = skip ->
            skip
        end

      {:error, reason} ->
        {:skip, "snakepit failed to start: #{inspect(reason)}"}
    end
  end

  defp await_pool_ready do
    case Snakepit.Pool.await_ready(Snakepit.Pool, @pool_ready_timeout) do
      :ok -> await_workers_available()
      {:error, reason} -> {:skip, "snakepit pool not ready: #{inspect(reason)}"}
    end
  end

  defp await_workers_available do
    deadline = System.monotonic_time(:millisecond) + @pool_ready_timeout
    wait_for_available_workers(deadline)
  end

  defp wait_for_available_workers(deadline_ms) do
    timeout_ms = max(0, deadline_ms - System.monotonic_time(:millisecond))

    check_workers = fn ->
      stats = Snakepit.Pool.get_stats(Snakepit.Pool)
      Map.get(stats, :available, 0) > 0
    end

    if SnakeBridge.TestHelpers.eventually(check_workers,
         timeout: timeout_ms,
         interval: @worker_ready_poll_ms
       ) do
      :ok
    else
      {:skip, "snakepit workers not available after #{@pool_ready_timeout}ms"}
    end
  end

  defp configure_snakepit(python) do
    Application.put_env(:snakepit, :pooling_enabled, true)
    Application.put_env(:snakepit, :pool_queue_timeout, @pool_queue_timeout)
    Application.put_env(:snakepit, :python_executable, python)
    Application.put_env(:snakepit, :heartbeat, %{enabled: false, dependent: false})

    adapter_module =
      Application.get_env(:snakepit, :adapter_module) || Snakepit.Adapters.GRPCPython

    Application.put_env(:snakepit, :adapter_module, adapter_module)

    pool_config =
      :snakepit
      |> Application.get_env(:pool_config, %{})
      |> normalize_config_input()
      |> Map.put_new(:pool_size, 2)
      |> Map.update(:adapter_args, default_adapter_args(), &ensure_adapter_args/1)
      |> Map.update(:adapter_env, default_adapter_env(), &ensure_adapter_env/1)
      |> Map.put_new(:name, :default)
      |> Map.put_new(:adapter_module, adapter_module)

    Application.put_env(:snakepit, :pools, [pool_config])
    Application.put_env(:snakepit, :pool_config, pool_config)
  end

  defp ensure_adapter_args(args) when is_list(args) do
    if Enum.any?(args, fn arg ->
         is_binary(arg) and (arg == "--adapter" or String.starts_with?(arg, "--adapter="))
       end) do
      args
    else
      args ++ default_adapter_args()
    end
  end

  defp ensure_adapter_args(_), do: default_adapter_args()

  defp default_adapter_args do
    ["--adapter", "snakebridge_adapter.SnakeBridgeAdapter"]
  end

  defp ensure_adapter_env(env) when is_list(env) do
    if env_has_pythonpath?(env) do
      env
    else
      env ++ default_adapter_env()
    end
  end

  defp ensure_adapter_env(_), do: default_adapter_env()

  defp env_has_pythonpath?(env) do
    Enum.any?(env, fn
      {key, _value} -> String.downcase(to_string(key)) == "pythonpath"
      key when is_atom(key) -> String.downcase(Atom.to_string(key)) == "pythonpath"
      key when is_binary(key) -> String.downcase(key) == "pythonpath"
      _ -> false
    end)
  end

  defp default_adapter_env do
    [{"PYTHONPATH", build_pythonpath()}]
  end

  defp snakepit_configured? do
    :persistent_term.get(@configured_key, false)
  end

  defp mark_snakepit_configured do
    :persistent_term.put(@configured_key, true)
  end

  defp clear_snakepit_configured do
    :persistent_term.erase(@configured_key)
  end

  defp ensure_original_env do
    if active_count() == 0 do
      :persistent_term.put(@original_env_key, capture_snakepit_env())
    end
  end

  defp increment_active_count do
    :persistent_term.put(@active_count_key, active_count() + 1)
  end

  defp teardown_real_python do
    count = active_count() - 1

    if count <= 0 do
      :persistent_term.erase(@active_count_key)
      stop_snakepit_if_running()
      clear_snakepit_configured()
      restore_snakepit_env(:persistent_term.get(@original_env_key, []))
      :persistent_term.erase(@original_env_key)
    else
      :persistent_term.put(@active_count_key, count)
    end
  end

  defp active_count do
    :persistent_term.get(@active_count_key, 0)
  end

  defp normalize_config_input(nil), do: %{}
  defp normalize_config_input(%{} = map), do: map
  defp normalize_config_input(list) when is_list(list), do: Map.new(list)
  defp normalize_config_input(_), do: %{}

  defp build_pythonpath do
    priv_snakebridge = Path.join(File.cwd!(), "priv/python")

    snakepit_priv_python =
      case :code.priv_dir(:snakepit) do
        {:error, _} -> nil
        priv_dir -> Path.join([to_string(priv_dir), "python"])
      end

    snakebridge_priv_python =
      case :code.priv_dir(:snakebridge) do
        {:error, _} -> nil
        priv_dir -> Path.join([to_string(priv_dir), "python"])
      end

    path_sep =
      case :os.type() do
        {:win32, _} -> ";"
        _ -> ":"
      end

    [
      System.get_env("PYTHONPATH"),
      priv_snakebridge,
      snakepit_priv_python,
      snakebridge_priv_python
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
    |> Enum.join(path_sep)
  end

  defp python_override? do
    System.get_env("SNAKEBRIDGE_TEST_PYTHON") ||
      Application.get_env(:snakepit, :python_executable) ||
      System.get_env("SNAKEPIT_PYTHON")
  end

  defp store_python_path(python) when is_binary(python) do
    :persistent_term.put(@python_key, python)
  end

  defp stored_python_path do
    :persistent_term.get(@python_key, nil)
  end

  defp pool_has_available_workers? do
    case Process.whereis(Snakepit.Pool) do
      nil ->
        false

      _pid ->
        stats = Snakepit.Pool.get_stats(Snakepit.Pool)
        Map.get(stats, :available, 0) > 0
    end
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  defp restart_snakepit_pool do
    stop_snakepit_if_running()
    clear_snakepit_configured()

    case resolve_python_with_cache() do
      {:ok, path} -> restart_with_python(path)
      {:skip, _reason} = skip -> skip
    end
  end

  defp restart_with_python(path) do
    case ensure_python_deps(path) do
      {:ok, resolved} ->
        store_python_path(resolved)
        ensure_snakepit_pool(resolved)

      {:skip, reason} ->
        {:skip, reason}
    end
  end

  defp ensure_snakepit_requirements do
    case snakepit_requirements_path() do
      nil ->
        {:skip, "snakepit requirements.txt not found; run mix snakepit.setup"}

      path ->
        try do
          Snakepit.PythonPackages.ensure!({:file, path},
            runner: SnakeBridge.PythonPackagesRunner,
            quiet: true
          )

          :ok
        rescue
          error ->
            {:skip, "snakepit python deps install failed: #{Exception.message(error)}"}
        catch
          :exit, reason ->
            {:skip, "snakepit python deps install failed: #{inspect(reason)}"}
        end
    end
  end

  defp snakepit_requirements_path do
    case :code.priv_dir(:snakepit) do
      {:error, _} ->
        nil

      priv_dir ->
        path = Path.join([to_string(priv_dir), "python", "requirements.txt"])
        if File.exists?(path), do: path, else: nil
    end
  end

  defp started_app?(app) do
    Enum.any?(Application.started_applications(), fn {started, _, _} -> started == app end)
  end

  defp capture_snakepit_env do
    Enum.map(@snakepit_env_keys, fn key ->
      {key, Application.get_env(:snakepit, key, :__missing__)}
    end)
  end

  defp restore_snakepit_env(entries) do
    Enum.each(entries, fn
      {key, :__missing__} -> Application.delete_env(:snakepit, key)
      {key, value} -> Application.put_env(:snakepit, key, value)
    end)
  end

  defp stop_snakepit_if_running do
    case Process.whereis(Snakepit.Supervisor) do
      nil ->
        _ = Application.stop(:snakepit)
        :ok

      supervisor_pid ->
        ref = Process.monitor(supervisor_pid)
        _ = Application.stop(:snakepit)

        receive do
          {:DOWN, ^ref, :process, ^supervisor_pid, _reason} ->
            :ok
        after
          @pool_ready_timeout ->
            :ok
        end
    end
  end
end
