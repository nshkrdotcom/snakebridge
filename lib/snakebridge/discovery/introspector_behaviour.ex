defmodule SnakeBridge.Discovery.IntrospectorBehaviour do
  @moduledoc """
  Behaviour for library introspection implementations.

  Allows swapping between real Snakepit-based introspection and
  mocked introspection for testing.
  """

  @doc """
  Discover a Python library's schema.

  ## Parameters

    * `module_path` - Python module path (e.g., "sympy")
    * `opts` - Options for discovery
      * `:depth` - Discovery depth for submodules
      * `:config_hash` - Config hash for cache validation
      * `:use_cache` - Whether to use cached results

  ## Returns

    * `{:ok, schema}` - Discovered schema map
    * `{:error, reason}` - Error during discovery
  """
  @callback discover(module_path :: String.t(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}
end
