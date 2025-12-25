import Config

# SnakeBridge configuration
#
# This file contains compile-time configuration for SnakeBridge.
# For runtime configuration, see config/runtime.exs

# Core SnakeBridge settings
config :snakebridge,
  # Automatically start Snakepit pools on first call
  auto_start_snakepit: true,
  # Python executable to use
  python_executable: "python3",
  # Additional Python paths (added to PYTHONPATH)
  python_path: [],
  # Log level for SnakeBridge operations
  log_level: :info

# Snakepit configuration (underlying Python runtime)
config :snakepit,
  # Python executable
  python: "python3",
  # Pool configuration
  pool_size: 5,
  pool_overflow: 10

# Import environment-specific config files
import_config "#{config_env()}.exs"
