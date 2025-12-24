import Config

# Development configuration
config :snakebridge,
  # Hot reload in dev
  compilation_mode: :runtime,
  cache_enabled: true,
  telemetry_enabled: true,
  # Use real adapter so manifest tooling works in dev
  snakepit_adapter: SnakeBridge.SnakepitAdapter
