defmodule SnakeBridge.HelperRegistryError do
  @moduledoc """
  Error raised when helper registry discovery fails.
  """

  defexception [:type, :message, :python_error, :suggestion]

  @type t :: %__MODULE__{
          type: :load_failed,
          message: String.t(),
          python_error: String.t() | nil,
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

  @doc """
  Build an error from Python stderr output.
  """
  @spec from_python_output(String.t()) :: t()
  def from_python_output(output) when is_binary(output) do
    %__MODULE__{
      type: :load_failed,
      message: "Helper registry failed to load",
      python_error: String.trim(output),
      suggestion: "Check helper paths or disable the helper pack"
    }
  end
end
