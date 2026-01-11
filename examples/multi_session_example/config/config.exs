import Config

config :snakebridge,
  verbose: false,
  strict: false,
  # auto_install uses :dev_test default
  docs: [source: :python, cache_enabled: false]

config :logger,
  level: :debug

# Snakepit is configured in runtime.exs using SnakeBridge.ConfigHelper
