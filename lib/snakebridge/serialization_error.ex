defmodule SnakeBridge.SerializationError do
  @moduledoc """
  Error raised when arguments cannot be serialized for Python execution.
  """

  defexception [:message, :suggestion]

  @type t :: %__MODULE__{
          message: String.t(),
          suggestion: String.t() | nil
        }

  @impl Exception
  def message(%__MODULE__{message: message, suggestion: suggestion}) do
    if suggestion do
      message <> "\n\nSuggestion: " <> suggestion
    else
      message
    end
  end

  @spec new(String.t() | nil) :: t()
  def new(message \\ nil) do
    %__MODULE__{
      message: message || "Arguments are not JSON-serializable",
      suggestion: "Use a helper or PyRef to cross the boundary"
    }
  end
end
