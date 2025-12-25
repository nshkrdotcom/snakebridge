defmodule SnakeBridge.SnakepitAdapter do
  @moduledoc """
  Real implementation that delegates to Snakepit.

  This is the production adapter - no mocking, just delegates
  to actual Snakepit functions.
  """

  @behaviour SnakeBridge.SnakepitBehaviour
  alias SnakeBridge.{Error, SnakepitLauncher}

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
        if Application.get_env(:snakebridge, :auto_start_snakepit, true) do
          start_snakepit_pool()
        else
          {:error,
           %Error{
             type: :snakepit_unavailable,
             message: "Snakepit is not running (Snakepit.Pool not found)",
             python_traceback: nil,
             details: %{}
           }}
        end

      _pid ->
        :ok
    end
  end

  defp start_snakepit_pool do
    SnakepitLauncher.ensure_pool_started!()
    :ok
  rescue
    exception ->
      {:error,
       %Error{
         type: :snakepit_unavailable,
         message: "Snakepit failed to start: #{Exception.message(exception)}",
         python_traceback: nil,
         details: %{}
       }}
  catch
    kind, reason ->
      {:error,
       %Error{
         type: :snakepit_unavailable,
         message: "Snakepit failed to start (#{kind}): #{inspect(reason)}",
         python_traceback: nil,
         details: %{}
       }}
  end
end
