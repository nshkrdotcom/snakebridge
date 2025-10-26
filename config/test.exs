import Config

# Test configuration
config :logger, level: :warning

config :snakebridge,
  compilation_strategy: :runtime,
  # Don't cache in tests
  cache_enabled: false,
  telemetry_enabled: false

# Use mock Snakepit in tests
config :snakebridge,
  snakepit_adapter: SnakeBridge.SnakepitMock
