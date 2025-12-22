defmodule SnakeBridge.SnakepitAdapter do
  @moduledoc """
  Real implementation that delegates to Snakepit.

  This is the production adapter - no mocking, just delegates
  to actual Snakepit functions.
  """

  @behaviour SnakeBridge.SnakepitBehaviour
  alias SnakeBridge.Error

  @impl true
  def execute_in_session(session_id, tool_name, args) do
    with :ok <- ensure_snakepit_running() do
      Snakepit.execute_in_session(session_id, tool_name, args)
    end
  end

  @impl true
  def execute_in_session(session_id, tool_name, args, opts) do
    with :ok <- ensure_snakepit_running() do
      Snakepit.execute_in_session(session_id, tool_name, args, opts)
    end
  end

  @impl true
  def get_stats do
    with :ok <- ensure_snakepit_running() do
      Snakepit.get_stats()
    end
  end

  @impl true
  def execute_in_session_stream(session_id, tool_name, args, callback_fn, opts \\ []) do
    with :ok <- ensure_snakepit_running() do
      Snakepit.execute_in_session_stream(session_id, tool_name, args, callback_fn, opts)
    end
  end

  defp ensure_snakepit_running do
    case Process.whereis(Snakepit.Pool) do
      nil ->
        {:error,
         %Error{
           type: :snakepit_unavailable,
           message: "Snakepit is not running (Snakepit.Pool not found)",
           python_traceback: nil,
           details: %{}
         }}

      _pid ->
        :ok
    end
  end
end
