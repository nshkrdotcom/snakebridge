defmodule SnakeBridge.RefNotFoundError do
  @moduledoc """
  Raised when a Python object reference cannot be found in the registry.

  This typically occurs when:
  - The ref was already released via `release_ref/1`
  - The session was released via `release_session/1`
  - The ref expired due to TTL
  - The ref was evicted due to registry size limits

  ## Fields

  - `:ref_id` - The ref ID that was not found
  - `:session_id` - The session ID the ref was looked up in
  - `:message` - Human-readable error message
  """

  defexception [:ref_id, :session_id, :message]

  @type t :: %__MODULE__{
          ref_id: String.t() | nil,
          session_id: String.t() | nil,
          message: String.t()
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    ref_id = Keyword.get(opts, :ref_id)
    session_id = Keyword.get(opts, :session_id)
    message = Keyword.get(opts, :message) || build_message(ref_id, session_id)

    %__MODULE__{
      ref_id: ref_id,
      session_id: session_id,
      message: message
    }
  end

  @impl Exception
  def message(%__MODULE__{message: message}), do: message

  defp build_message(ref_id, session_id) do
    base = "SnakeBridge reference '#{ref_id || "unknown"}' not found"

    if session_id do
      base <> " in session '#{session_id}'. The ref may have been released, expired, or evicted."
    else
      base <> ". The ref may have been released, expired, or evicted."
    end
  end
end
