import Config

# Runtime configuration
#
# This file is executed after compilation and can read from environment
# variables.

if strict = System.get_env("SNAKEBRIDGE_STRICT") do
  config :snakebridge, strict: strict in ["1", "true", "TRUE", "yes", "YES"]
end

if verbose = System.get_env("SNAKEBRIDGE_VERBOSE") do
  config :snakebridge, verbose: verbose in ["1", "true", "TRUE", "yes", "YES"]
end
