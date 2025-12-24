import Config

# Test configuration
config :logger, level: :warning

config :snakebridge,
  compilation_mode: :runtime,
  # Don't cache in tests
  cache_enabled: false,
  telemetry_enabled: false

# Use mock Snakepit in tests by default
config :snakebridge,
  snakepit_adapter: SnakeBridge.SnakepitMock

# Note: Real Python configuration is loaded dynamically in test setup
# when SNAKEPIT_PYTHON is set and tests are tagged with :real_python
# See test/integration/real_python_test.exs for setup details
