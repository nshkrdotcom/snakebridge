defmodule SnakeBridge.SnakepitTestHelper do
  @moduledoc """
  Helpers to start a real Snakepit instance for integration tests.
  """

  @doc """
  Prepare Python-related environment variables for real Python tests.
  Returns `{python_exe, pythonpath, pool_config}` ready to hand to `start_snakepit!/1`.
  """
  def prepare_python_env!(adapter_spec \\ "snakebridge_adapter.adapter.SnakeBridgeAdapter") do
    project_root = File.cwd!()
    project_venv = Path.join(project_root, ".venv")
    venv_python = Path.join(project_venv, "bin/python3")

    python_exe =
      cond do
        File.exists?(venv_python) ->
          venv_python

        true ->
          base_python =
            [System.get_env("SNAKEPIT_PYTHON"), System.find_executable("python3")]
            |> Enum.find(& &1) ||
              raise "Python executable not found. Set SNAKEPIT_PYTHON to a Python 3.9+ interpreter."

          File.mkdir_p!(project_venv)

          case System.cmd(base_python, ["-m", "venv", project_venv]) do
            {_out, 0} -> :ok
            {out, code} -> raise "Failed to create venv at #{project_venv} (code #{code}): #{out}"
          end

          venv_python
      end

    snakebridge_python = Path.join([project_root, "priv", "python"])
    snakepit_python = Application.app_dir(:snakepit, "priv/python")

    pythonpath =
      [snakebridge_python, snakepit_python]
      |> Enum.filter(&File.dir?/1)
      |> Enum.join(":")

    System.put_env("PYTHONPATH", pythonpath)
    System.put_env("SNAKEPIT_PYTHON", python_exe)
    ensure_python_dependencies!(python_exe, pythonpath)

    adapter_env =
      [{"PYTHONPATH", pythonpath}, {"SNAKEPIT_PYTHON", python_exe}]
      |> maybe_put_virtual_env(python_exe)

    pool_config = %{
      name: :default,
      worker_profile: :process,
      pool_size: 1,
      adapter_module: Snakepit.Adapters.GRPCPython,
      adapter_args: ["--adapter", adapter_spec],
      adapter_env: adapter_env
    }

    {python_exe, pythonpath, pool_config}
  end

  @doc """
  Configure and start Snakepit for real Python integration tests.

  Accepts an optional `:pool_config` override.
  Returns a callback that restores the prior environment.
  """
  def start_snakepit!(opts \\ []) do
    original_env = Application.get_all_env(:snakepit)
    env_doctor_bypass = SnakeBridge.EnvDoctorBypass

    pool_config =
      opts
      |> Keyword.get(:pool_config, %{})
      |> merge_pool_defaults()

    python_exec = resolve_python_exec(opts)

    maybe_stop_running_snakepit()

    # Ensure a predictable, minimal pool config for tests
    Application.put_env(:snakepit, :pooling_enabled, true)
    Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.GRPCPython)
    Application.put_env(:snakepit, :pool_config, pool_config)
    Application.put_env(:snakepit, :pools, [pool_config])
    Application.put_env(:snakepit, :python_executable, python_exec)
    Application.put_env(:snakepit, :bootstrap_project_root, Application.app_dir(:snakepit))
    # Bypass EnvDoctor checks in tests to avoid local Python/dependency drift
    Application.put_env(:snakepit, :env_doctor_module, env_doctor_bypass)
    # Use an ephemeral gRPC port to reduce collisions in CI/dev
    Application.put_env(:snakepit, :grpc_port, 50_152)

    case Application.ensure_all_started(:snakepit) do
      {:ok, _} ->
        case wait_for_pool_ready() do
          :ok ->
            :ok

          other ->
            raise "Snakepit failed to start pooling: #{inspect(other)}"
        end

      {:error, reason} ->
        raise "Failed to start Snakepit for real Python tests: #{inspect(reason)}"
    end

    fn ->
      Application.stop(:snakepit)

      Enum.each(original_env, fn {key, value} ->
        Application.put_env(:snakepit, key, value)
      end)
    end
  end

  defp merge_pool_defaults(pool_config) do
    default_pool_config = %{
      name: :default,
      worker_profile: :process,
      pool_size: 1,
      adapter_module: Snakepit.Adapters.GRPCPython,
      adapter_args: [],
      adapter_env: []
    }

    Map.merge(default_pool_config, pool_config)
  end

  defp resolve_python_exec(opts) do
    [
      opts[:python_executable],
      System.get_env("SNAKEPIT_PYTHON"),
      Path.join([File.cwd!(), ".venv", "bin", "python3"]),
      System.find_executable("python3")
    ]
    |> Enum.find(fn path -> path && File.exists?(path) end) ||
      raise "Python executable not found. Set SNAKEPIT_PYTHON to a Python 3.9+ interpreter."
  end

  defp maybe_stop_running_snakepit do
    started? =
      Application.started_applications()
      |> Enum.any?(fn {app, _desc, _vsn} -> app == :snakepit end)

    if started? do
      :ok = Application.stop(:snakepit)
    end
  end

  defp ensure_python_dependencies!(python_exec, pythonpath) do
    env = [{"PYTHONPATH", pythonpath}]

    requirements = Application.app_dir(:snakepit, "priv/python/requirements.txt")
    adapter_dir = Path.expand(Path.join([File.cwd!(), "priv/python"]))

    # Ensure pip exists
    _ = System.cmd(python_exec, ["-m", "ensurepip", "--upgrade"], env: env)

    {out1, code1} =
      System.cmd(python_exec, ["-m", "pip", "install", "-r", requirements], env: env)

    {out2, code2} = System.cmd(python_exec, ["-m", "pip", "install", "-e", adapter_dir], env: env)

    case System.cmd(python_exec, ["-c", "import grpc"], env: env) do
      {_out, 0} ->
        :ok

      {output, _} ->
        raise "Python deps missing. Install grpc/protobuf manually. Outputs: #{out1} #{out2} #{output} (pip codes #{code1}/#{code2})"
    end
  end

  defp wait_for_pool_ready do
    Enum.reduce_while(1..20, :error, fn attempt, _ ->
      case Process.whereis(Snakepit.Pool) do
        nil ->
          Process.sleep(100 * attempt)
          {:cont, :error}

        _pid ->
          {:halt, :ok}
      end
    end)
  end

  defp maybe_put_virtual_env(env, python_exec) do
    venv_root = python_exec |> Path.dirname() |> Path.dirname()

    if File.exists?(Path.join(venv_root, "bin/python3")) do
      [{"VIRTUAL_ENV", venv_root} | env]
    else
      env
    end
  end
end
