defmodule SnakeBridge.RealPythonCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Snakepit.Adapters.GRPCPython

  @pool_ready_timeout 30_000
  @pool_queue_timeout 20_000
  @worker_ready_poll_ms 100
  @configured_key {__MODULE__, :real_python_configured}
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
      import SnakeBridge.RealPythonCase, only: [setup_real_python: 1]
      setup_all :setup_real_python
    end
  end

  def setup_real_python(context) do
    ensure_original_env()
    increment_active_count()

    on_exit(fn -> teardown_real_python() end)

    case ensure_real_python() do
      :ok -> context
      {:skip, reason} -> %{context | skip: reason}
    end
  end

  defp ensure_real_python do
    with {:ok, python} <- resolve_python(),
         :ok <- ensure_python_deps(python) do
      ensure_snakepit_pool(python)
    end
  end

  defp resolve_python do
    python =
      Application.get_env(:snakepit, :python_executable) ||
        System.get_env("SNAKEPIT_PYTHON") ||
        GRPCPython.executable_path() ||
        System.find_executable("python3")

    if is_binary(python) do
      {:ok, python}
    else
      {:skip, "python3 not available"}
    end
  end

  defp ensure_python_deps(python) do
    env = [{"PYTHONPATH", build_pythonpath()}]

    case System.cmd(python, ["-c", "import grpc, google.protobuf, snakebridge_adapter"], env: env) do
      {_output, 0} ->
        :ok

      {output, _status} ->
        {:skip, "python deps missing (grpc/protobuf/snakebridge_adapter): #{String.trim(output)}"}
    end
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
