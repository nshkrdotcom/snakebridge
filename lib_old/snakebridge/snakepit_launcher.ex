defmodule SnakeBridge.SnakepitLauncher do
  @moduledoc """
  Helper to start a Snakepit pool for mix tasks that require live Python.
  """

  alias SnakeBridge.Python

  @default_adapter "snakebridge_adapter.adapter.SnakeBridgeAdapter"

  @spec ensure_pool_started!(keyword()) :: :ok
  def ensure_pool_started!(opts \\ []) do
    if SnakeBridge.Runtime.snakepit_adapter() == SnakeBridge.SnakepitMock do
      :ok
    else
      case Process.whereis(Snakepit.Pool) do
        nil -> start_pool!(opts)
        _pid -> :ok
      end
    end
  end

  defp start_pool!(opts) do
    if snakepit_started?() do
      :ok = Application.stop(:snakepit)
    end

    {python_exec, venv_used?} = resolve_python_exec(opts)

    if Keyword.get(opts, :auto_install, true) do
      ensure_python_dependencies!(python_exec)
    end

    pythonpath = build_pythonpath()

    adapter_env =
      [{"PYTHONPATH", pythonpath}, {"SNAKEPIT_PYTHON", python_exec}]
      |> maybe_put_virtual_env(python_exec, venv_used?)

    pool_size = Keyword.get(opts, :pool_size, Application.get_env(:snakebridge, :pool_size, 1))

    adapter_spec = Keyword.get(opts, :adapter_spec, @default_adapter)

    grpc_port = Keyword.get(opts, :grpc_port, random_grpc_port())

    pool_config = %{
      name: :default,
      worker_profile: :process,
      pool_size: pool_size,
      adapter_module: Snakepit.Adapters.GRPCPython,
      adapter_args: ["--adapter", adapter_spec],
      adapter_env: adapter_env
    }

    Application.put_env(:snakepit, :pooling_enabled, true)
    Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.GRPCPython)
    Application.put_env(:snakepit, :pool_config, pool_config)
    Application.put_env(:snakepit, :pools, [pool_config])
    Application.put_env(:snakepit, :python_executable, python_exec)
    Application.put_env(:snakepit, :bootstrap_project_root, Application.app_dir(:snakepit))
    Application.put_env(:snakepit, :grpc_port, grpc_port)

    case Application.ensure_all_started(:snakepit) do
      {:ok, _} -> :ok
      {:error, reason} -> raise "Failed to start Snakepit: #{inspect(reason)}"
    end

    case Snakepit.Pool.await_ready(Snakepit.Pool, 30_000) do
      :ok -> :ok
      {:error, reason} -> raise "Snakepit pool failed to initialize: #{inspect(reason)}"
    end
  end

  defp snakepit_started? do
    Application.started_applications()
    |> Enum.any?(fn {app, _desc, _vsn} -> app == :snakepit end)
  end

  defp resolve_python_exec(opts) do
    venv_path = Path.expand(Keyword.get(opts, :venv, ".venv"))
    venv_python = Path.join(venv_path, "bin/python3")

    python_exec =
      cond do
        # Explicit python path takes precedence
        python = Keyword.get(opts, :python) ->
          python

        # Config python_path
        config_python = Application.get_env(:snakebridge, :python_path) ->
          config_python

        # Environment variable
        env_python = System.get_env("SNAKEPIT_PYTHON") ->
          env_python

        # Venv exists - use it
        File.exists?(venv_python) ->
          venv_python

        # Auto-create venv if we can find a base Python
        System.find_executable("python3") || System.find_executable("python") ->
          # Auto-setup: create venv and install deps
          {python, _pip} = Python.ensure_environment!(venv: venv_path, quiet: false)
          python

        true ->
          raise "Python not found. Please install Python 3.8+ and ensure it's in PATH."
      end

    venv_used? = File.exists?(venv_python) and Path.expand(python_exec) == venv_python
    {python_exec, venv_used?}
  end

  defp ensure_python_dependencies!(python_exec) do
    Python.run!(python_exec, ["-m", "ensurepip", "--upgrade"])
    Python.run!(python_exec, ["-m", "pip", "install", "--upgrade", "pip"])

    snakepit_reqs = Application.app_dir(:snakepit, "priv/python/requirements.txt")
    adapter_dir = resolve_snakebridge_adapter_dir()

    if File.exists?(snakepit_reqs) do
      Python.run!(python_exec, ["-m", "pip", "install", "-r", snakepit_reqs])
    end

    if adapter_dir && File.exists?(Path.join(adapter_dir, "setup.py")) do
      Python.run!(python_exec, ["-m", "pip", "install", "-e", adapter_dir])
    end
  end

  defp resolve_snakebridge_adapter_dir do
    local = Path.expand("priv/python")
    app_dir = Application.app_dir(:snakebridge, "priv/python")

    cond do
      File.exists?(local) -> local
      File.exists?(app_dir) -> app_dir
      true -> nil
    end
  end

  defp build_pythonpath do
    candidates =
      [
        Path.expand("priv/python"),
        Path.expand("priv/python/bridges"),
        Application.app_dir(:snakebridge, "priv/python"),
        Application.app_dir(:snakebridge, "priv/python/bridges"),
        Application.app_dir(:snakepit, "priv/python")
      ]
      |> Enum.filter(&File.dir?/1)
      |> Enum.uniq()

    Enum.join(candidates, ":")
  end

  defp maybe_put_virtual_env(env, python_exec, venv_used?) do
    if venv_used? do
      venv_root = python_exec |> Path.dirname() |> Path.dirname()
      [{"VIRTUAL_ENV", venv_root} | env]
    else
      env
    end
  end

  defp random_grpc_port do
    50_000 + :rand.uniform(9_000)
  end
end
