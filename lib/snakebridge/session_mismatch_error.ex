defmodule SnakeBridge.SessionMismatchError do
  @moduledoc """
  Raised when a ref is used with a different session than it was created in.

  SnakeBridge refs are session-scoped: a ref created in session A cannot be
  used in session B. This error indicates a ref is being used across session
  boundaries.

  ## Fields

  - `:ref_id` - The ref ID that caused the mismatch
  - `:expected_session` - The session ID the ref belongs to
  - `:actual_session` - The session ID the ref was used in
  - `:message` - Human-readable error message
  """

  defexception [:ref_id, :expected_session, :actual_session, :message]

  @type t :: %__MODULE__{
          ref_id: String.t() | nil,
          expected_session: String.t() | nil,
          actual_session: String.t() | nil,
          message: String.t()
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    ref_id = Keyword.get(opts, :ref_id)
    expected_session = Keyword.get(opts, :expected_session)
    actual_session = Keyword.get(opts, :actual_session)

    message =
      Keyword.get(opts, :message) || build_message(ref_id, expected_session, actual_session)

    %__MODULE__{
      ref_id: ref_id,
      expected_session: expected_session,
      actual_session: actual_session,
      message: message
    }
  end

  @impl Exception
  def message(%__MODULE__{message: message}), do: message

  defp build_message(ref_id, expected, actual) do
    "SnakeBridge reference '#{ref_id || "unknown"}' belongs to session '#{expected || "unknown"}' " <>
      "but was used in session '#{actual || "unknown"}'. Refs cannot be shared across sessions."
  end
end
