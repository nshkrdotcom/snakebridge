import Config

# SnakeBridge compile-time configuration.
config :snakebridge,
  generated_dir: "lib/snakebridge_generated",
  generated_layout: :split,
  metadata_dir: ".snakebridge",
  verbose: false,
  strict: false,
  scan_paths: ["lib"],
  scan_exclude: [],
  introspector: [max_concurrency: 4, timeout: 30_000],
  docs: [cache_enabled: true, cache_ttl: :infinity, source: :python],
  runtime_client: Snakepit,
  ledger: [enabled: true, promote: :manual]

# Snakepit runtime configuration lives under :snakepit.

# Import environment-specific config files
import_config "#{config_env()}.exs"
