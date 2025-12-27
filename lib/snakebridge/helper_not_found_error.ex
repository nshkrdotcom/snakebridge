defmodule SnakeBridge.HelperNotFoundError do
  @moduledoc """
  Error raised when a helper name is not registered.
  """

  defexception [:message, :helper, :suggestion]

  @type t :: %__MODULE__{
          message: String.t(),
          helper: String.t() | nil,
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

  @spec new(String.t()) :: t()
  def new(helper) do
    %__MODULE__{
      helper: helper,
      message: "Helper '#{helper}' not found",
      suggestion: "Add a helper under priv/python/helpers or enable the helper pack"
    }
  end
end
