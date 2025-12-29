import Config

path_sep =
  case :os.type() do
    {:win32, _} -> ";"
    _ -> ":"
  end

app_root = Path.expand("..", __DIR__)
snakebridge_root = Path.expand("../..", app_root)
venv_python = Path.join([snakebridge_root, ".venv", "bin", "python"])

snakepit_priv = Path.join([app_root, "deps", "snakepit", "priv", "python"])
snakebridge_priv = Path.join([snakebridge_root, "priv", "python"])
repo_priv = Path.join([app_root, "priv", "python"])

pythonpath =
  [System.get_env("PYTHONPATH"), snakepit_priv, repo_priv, snakebridge_priv]
  |> Enum.reject(&(&1 in [nil, ""]))
  |> Enum.uniq()
  |> Enum.join(path_sep)

config :snakebridge,
  verbose: false,
  strict: true,
  auto_install: :dev,
  introspector: [env: %{"PYTHONPATH" => pythonpath}],
  docs: [source: :python, cache_enabled: false]

config :snakepit,
  pooling_enabled: true,
  python_executable: venv_python,
  adapter_module: Snakepit.Adapters.GRPCPython,
  pool_config: %{
    pool_size: 2,
    adapter_args: ["--adapter", "snakebridge_adapter.SnakeBridgeAdapter"],
    adapter_env: %{"PYTHONPATH" => pythonpath}
  }

config :logger,
  level: :warning
