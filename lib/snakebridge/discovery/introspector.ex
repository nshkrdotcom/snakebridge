defmodule SnakeBridge.Discovery.Introspector do
  @moduledoc """
  Protocol and default implementation for library introspection.
  """

  @doc """
  Discover library schema.
  """
  @spec discover(module(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def discover(_impl, _module_path, _opts) do
    # Placeholder - will implement
    {:error, :not_implemented}
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
end
