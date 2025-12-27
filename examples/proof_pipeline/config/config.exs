import Config

path_sep =
  case :os.type() do
    {:win32, _} -> ";"
    _ -> ":"
  end

app_root = Path.expand("..", __DIR__)
snakebridge_root = Path.expand("../..", app_root)

snakepit_priv = Path.join([app_root, "deps", "snakepit", "priv", "python"])
snakebridge_priv = Path.join([snakebridge_root, "priv", "python"])

repo_priv = Path.join([app_root, "priv", "python"])

pythonpath =
  [System.get_env("PYTHONPATH"), snakepit_priv, repo_priv, snakebridge_priv]
  |> Enum.reject(&(&1 in [nil, ""]))
  |> Enum.uniq()
  |> Enum.join(path_sep)

config :snakebridge,
  verbose: true,
  strict: false,
  auto_install: :dev,
  docs: [source: :python, cache_enabled: false]

config :snakepit,
  pooling_enabled: true,
  adapter_module: Snakepit.Adapters.GRPCPython,
  pool_config: %{
    pool_size: 4,
    adapter_args: ["--adapter", "snakebridge_adapter.SnakeBridgeAdapter"],
    adapter_env: %{"PYTHONPATH" => pythonpath}
  }

config :snakepit, :python,
  strategy: :uv,
  managed: true,
  python_version: "3.12.3",
  runtime_dir: "priv/snakepit/python",
  cache_dir: "priv/snakepit/python/cache"

config :snakepit, :python_packages, installer: :uv

config :logger,
  level: :info
