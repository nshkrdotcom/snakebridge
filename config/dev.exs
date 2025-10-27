import Config

# Development configuration
config :snakebridge,
  # Hot reload in dev
  compilation_strategy: :runtime,
  cache_enabled: true,
  telemetry_enabled: true,
  # Use mock in dev (until Snakepit is configured)
  snakepit_adapter: SnakeBridge.SnakepitMock
