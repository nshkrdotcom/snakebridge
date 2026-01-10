import Config

# Development-specific configuration
config :snakebridge,
  verbose: true

# Logger configuration for development
config :logger,
  level: :debug,
  compile_time_purge_matching: [
    [level_lower_than: :debug]
  ]

# Console logger format
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :mfa, :file, :line]
