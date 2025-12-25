import Config

# Configure SnakeBridge with the Python libraries you need
# These will be generated automatically on `mix compile`
config :snakebridge,
  adapters: [
    # Standard library - always available
    :json,
    :math,

    # SymPy - symbolic mathematics (uv installs automatically)
    :sympy
  ]

# Configure logging (optional)
config :logger,
  level: :info
