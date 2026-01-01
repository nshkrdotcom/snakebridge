defmodule SnakeBridge.InvalidRefError do
  @moduledoc """
  Raised when a ref payload is malformed or invalid.

  This occurs when the ref structure is missing required fields or has
  an unrecognized format.

  ## Fields

  - `:reason` - Why the ref is invalid (atom or string)
  - `:message` - Human-readable error message
  """

  defexception [:reason, :message]

  @type t :: %__MODULE__{
          reason: atom() | String.t() | nil,
          message: String.t()
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    reason = Keyword.get(opts, :reason)
    message = Keyword.get(opts, :message) || build_message(reason)

    %__MODULE__{
      reason: reason,
      message: message
    }
  end

  @impl Exception
  def message(%__MODULE__{message: message}), do: message

  defp build_message(reason) when is_atom(reason) do
    case reason do
      :missing_id -> "Invalid SnakeBridge reference: missing 'id' field"
      :missing_type -> "Invalid SnakeBridge reference: missing '__type__' field"
      :invalid_format -> "Invalid SnakeBridge reference: unrecognized payload format"
      _ -> "Invalid SnakeBridge reference: #{reason}"
    end
  end

  defp build_message(reason) when is_binary(reason) do
    "Invalid SnakeBridge reference: #{reason}"
  end

  defp build_message(_) do
    "Invalid SnakeBridge reference"
  end
end
