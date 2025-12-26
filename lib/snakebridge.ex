defmodule SnakeBridge do
  @moduledoc """
  SnakeBridge v3 - compile-time Python adapter generation for Elixir.

  SnakeBridge scans your codebase at compile time, introspects Python via
  the Snakepit runtime, and generates deterministic Elixir wrappers under
  `lib/snakebridge_generated/`. Runtime execution belongs to Snakepit.
  """

  defdelegate call(module, function, args \\ [], opts \\ []), to: SnakeBridge.Runtime
  defdelegate stream(module, function, args \\ [], opts \\ [], callback), to: SnakeBridge.Runtime

  @doc """
  Returns the SnakeBridge version.
  """
  @spec version() :: String.t()
  def version do
    Application.spec(:snakebridge, :vsn) |> to_string()
  end
end
