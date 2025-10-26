import Config

if config_env() == :prod do
  # Production runtime configuration
  config :snakebridge,
    # Pre-compiled in prod
    compilation_strategy: :compile_time,
    cache_enabled: true,
    cache_path: System.get_env("SNAKEBRIDGE_CACHE_PATH", "priv/snakebridge/cache"),
    telemetry_enabled: true
end
