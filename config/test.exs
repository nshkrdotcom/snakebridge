import Config

# Test-specific configuration
config :snakebridge,
  strict: false,
  verbose: false,
  docs: [cache_enabled: false, source: :metadata]

# Logger configuration for tests
config :logger,
  level: :warning,
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
