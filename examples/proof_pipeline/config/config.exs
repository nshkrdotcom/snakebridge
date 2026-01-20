import Config

config :snakebridge,
  verbose: false,
  strict: false,
  # auto_install uses :dev_test default
  docs: [source: :python, cache_enabled: false]

config :logger,
  level: :warning

config :snakepit,
  auto_install_python_deps: true

# Snakepit is configured in runtime.exs using SnakeBridge.ConfigHelper
