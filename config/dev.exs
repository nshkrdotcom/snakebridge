import Config

# Development-specific configuration

# Enable verbose logging in development
config :snakebridge,
  log_level: :debug

# Increase pool size for development (faster feedback)
config :snakepit,
  pool_size: 10,
  pool_overflow: 20

# Logger configuration for development
config :logger,
  level: :debug,
  backends: [:console],
  compile_time_purge_matching: [
    [level_lower_than: :debug]
  ]

# Console logger format
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :mfa, :file, :line]
