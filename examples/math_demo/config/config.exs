import Config

# SnakeBridge v3 reads libraries from mix.exs dependency options.
# This file only configures compile-time behavior.
config :snakebridge,
  verbose: true,
  strict: false,
  docs: [source: :python, cache_enabled: false]

config :logger,
  level: :info
