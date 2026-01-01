import Config

config :snakebridge,
  verbose: false,
  strict: false,
  auto_install: :dev,
  docs: [source: :python, cache_enabled: false]

config :logger,
  level: :warning

# Snakepit is configured in runtime.exs using SnakeBridge.ConfigHelper
