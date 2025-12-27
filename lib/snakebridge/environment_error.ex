defmodule SnakeBridge.EnvironmentError do
  @moduledoc """
  Error raised when required Python packages are missing.
  """

  defexception [:message, :missing_packages, :suggestion]

  @type t :: %__MODULE__{
          message: String.t(),
          missing_packages: [String.t()],
          suggestion: String.t()
        }

  @impl Exception
  def message(%__MODULE__{message: message, suggestion: suggestion}) do
    if suggestion do
      message <> "\n\nSuggestion: " <> suggestion
    else
      message
    end
  end
end
