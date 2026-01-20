import Config

config :logger,
  level: :warning

config :snakepit,
  auto_install_python_deps: true

# Snakepit is configured in runtime.exs using SnakeBridge.ConfigHelper
