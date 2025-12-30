defmodule SnakeBridge do
  @moduledoc """
  SnakeBridge v3 - compile-time Python adapter generation for Elixir.

  SnakeBridge scans your codebase at compile time, introspects Python via
  the Snakepit runtime, and generates deterministic Elixir wrappers under
  `lib/snakebridge_generated/`. Runtime execution belongs to Snakepit.
  """

  require SnakeBridge.WithContext

  defdelegate call(module, function, args \\ [], opts \\ []), to: SnakeBridge.Runtime
  defdelegate call_helper(helper, args \\ [], opts \\ []), to: SnakeBridge.Runtime
  defdelegate stream(module, function, args \\ [], opts \\ [], callback), to: SnakeBridge.Runtime

  defmacro with_python(ref, do: block) do
    quote do
      require SnakeBridge.WithContext
      SnakeBridge.WithContext.with_python(unquote(ref), do: unquote(block))
    end
  end

  @doc """
  Returns the SnakeBridge version.
  """
  @spec version() :: String.t()
  def version do
    Application.spec(:snakebridge, :vsn) |> to_string()
  end
end
