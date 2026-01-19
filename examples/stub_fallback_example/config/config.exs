import Config

config :snakebridge,
  verbose: false,
  strict: false,
  docs: [source: :python, cache_enabled: false]

config :logger,
  level: :warning
