if Code.ensure_loaded?(Snakepit.PyRef) == false do
  defmodule Snakepit.PyRef do
    @moduledoc """
    Reference to a Python object managed by Snakepit.

    This is a stub type definition used when the Snakepit library is not loaded.
    When Snakepit is available, its actual `Snakepit.PyRef` module takes precedence.
    """
    @type t :: SnakeBridge.Ref.t()
  end
end

if Code.ensure_loaded?(Snakepit.ZeroCopyRef) == false do
  defmodule Snakepit.ZeroCopyRef do
    @moduledoc """
    Reference to a zero-copy Python buffer managed by Snakepit.

    This is a stub type definition used when the Snakepit library is not loaded.
    When Snakepit is available, its actual `Snakepit.ZeroCopyRef` module takes precedence.
    """
    @type t :: term()
  end
end

if Code.ensure_loaded?(Snakepit.Error) == false do
  defmodule Snakepit.Error do
    @moduledoc """
    Error struct for Snakepit operations.

    This is a stub type definition used when the Snakepit library is not loaded.
    When Snakepit is available, its actual `Snakepit.Error` module takes precedence.
    """
    @type t :: term()

    @doc "Creates a validation error."
    def validation_error(message, metadata \\ %{}) do
      %{type: :validation_error, message: message, metadata: metadata}
    end
  end
end
