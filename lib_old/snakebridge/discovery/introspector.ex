defmodule SnakeBridge.Discovery.Introspector do
  @moduledoc """
  Protocol and default implementation for library introspection.

  Uses the adapter pattern - takes an implementation module as first parameter,
  allowing tests to inject a mock while production uses the real Snakepit-based
  implementation.
  """

  @behaviour SnakeBridge.Discovery.IntrospectorBehaviour

  @doc """
  Discover library schema using provided implementation.

  The `impl` parameter should be a module implementing IntrospectorBehaviour.
  In tests, this will be IntrospectorMock. In production, use the default
  implementation or create your own.

  ## Examples

      # Using mock in tests
      {:ok, schema} = Introspector.discover(IntrospectorMock, "sympy", [])

      # Using real implementation
      {:ok, schema} = Introspector.discover(Introspector, "sympy", depth: 3)
  """
  @spec discover(module(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def discover(impl, module_path, opts) when is_atom(impl) do
    # If impl is Introspector (this module), use real implementation
    # Otherwise, delegate to the provided implementation (e.g., mock)
    if impl == __MODULE__ do
      do_discover(module_path, opts)
    else
      impl.discover(module_path, opts)
    end
  end

  @doc """
  Real implementation using Snakepit adapter.
  """
  @impl true
  def discover(module_path, opts) do
    do_discover(module_path, opts)
  end

  defp do_discover(module_path, opts) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    depth = Keyword.get(opts, :depth, 2)
    config_hash = Keyword.get(opts, :config_hash)

    adapter = SnakeBridge.Runtime.snakepit_adapter()

    tool_args = %{
      "module_path" => module_path,
      "discovery_depth" => depth
    }

    tool_args =
      if config_hash do
        Map.put(tool_args, "config_hash", config_hash)
      else
        tool_args
      end

    case adapter.execute_in_session(session_id, "describe_library", tool_args, []) do
      {:ok, %{"success" => true} = response} ->
        # Extract the schema portion from the response
        schema = Map.drop(response, ["success"])
        {:ok, schema}

      {:ok, %{"success" => false, "error" => error}} ->
        {:error, error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Parse Python descriptor to normalized format.
  """
  @spec parse_descriptor(map()) :: map()
  def parse_descriptor(descriptor) when is_map(descriptor) do
    descriptor
    |> Map.put_new(:methods, [])
    |> Map.put_new(:docstring, "")
    |> Map.put_new(:properties, [])
  end

  defp generate_session_id do
    SnakeBridge.SessionId.generate("introspection")
  end
end
