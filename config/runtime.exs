import Config

# Runtime configuration
#
# This file is executed after compilation and can read from environment
# variables. It's useful for production deployments where configuration
# needs to be set at runtime rather than compile time.

# Load Python executable from environment
if python_executable = System.get_env("SNAKEBRIDGE_PYTHON_EXECUTABLE") do
  config :snakebridge,
    python_executable: python_executable

  config :snakepit,
    python: python_executable
end

# Load Python path additions from environment
# Format: SNAKEBRIDGE_PYTHON_PATH=/path/one:/path/two
if python_path = System.get_env("SNAKEBRIDGE_PYTHON_PATH") do
  paths = String.split(python_path, ":", trim: true)

  config :snakebridge,
    python_path: paths
end

# Configure Snakepit pool size from environment
if pool_size = System.get_env("SNAKEPIT_POOL_SIZE") do
  {size, ""} = Integer.parse(pool_size)

  config :snakepit,
    pool_size: size
end

if pool_overflow = System.get_env("SNAKEPIT_POOL_OVERFLOW") do
  {overflow, ""} = Integer.parse(pool_overflow)

  config :snakepit,
    pool_overflow: overflow
end

# Auto-start configuration
if auto_start = System.get_env("SNAKEBRIDGE_AUTO_START") do
  enabled = auto_start in ["1", "true", "yes", "on"]

  config :snakebridge,
    auto_start_snakepit: enabled
end

# Log level configuration
if log_level = System.get_env("SNAKEBRIDGE_LOG_LEVEL") do
  level = String.to_existing_atom(log_level)

  config :snakebridge,
    log_level: level

  config :logger,
    level: level
end
