import Config

config :snakebridge,
  verbose: true,
  strict: false,
  docs: [source: :python, cache_enabled: false]

config :logger,
  level: :info
