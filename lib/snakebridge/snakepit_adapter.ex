defmodule SnakeBridge.SnakepitAdapter do
  @moduledoc """
  Real implementation that delegates to Snakepit.

  This is the production adapter - no mocking, just delegates
  to actual Snakepit functions.
  """

  @behaviour SnakeBridge.SnakepitBehaviour

  @impl true
  def execute_in_session(session_id, tool_name, args) do
    Snakepit.execute_in_session(session_id, tool_name, args)
  end

  @impl true
  def execute_in_session(session_id, tool_name, args, opts) do
    Snakepit.execute_in_session(session_id, tool_name, args, opts)
  end

  @impl true
  def get_stats do
    Snakepit.get_stats()
  end
end
