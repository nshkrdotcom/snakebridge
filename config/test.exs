import Config

# Test-specific configuration

# Disable automatic Snakepit startup in tests (use mocks)
config :snakebridge,
  auto_start_snakepit: false,
  log_level: :warning

# Smaller pool size for tests
config :snakepit,
  pool_size: 2,
  pool_overflow: 5

# Logger configuration for tests
config :logger,
  level: :warning,
  backends: [:console],
  compile_time_purge_matching: [
    [level_lower_than: :warning]
  ]

# Suppress logs during tests unless VERBOSE=1
if System.get_env("VERBOSE") do
  config :logger, level: :debug
end

# Console logger format for tests (minimal)
config :logger, :console,
  format: "$metadata[$level] $message\n",
  metadata: [:test, :module]

# ExUnit configuration
config :ex_unit,
  capture_log: true,
  assert_receive_timeout: 500,
  refute_receive_timeout: 100

# Mox configuration (if using Mox for testing)
config :snakebridge, :mocks, python_runtime: SnakeBridge.MockPythonRuntime
