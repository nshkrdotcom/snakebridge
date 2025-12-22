defmodule SnakeBridge.SnakepitBehaviour do
  @moduledoc """
  Behaviour that wraps Snakepit functions we depend on.

  This allows us to mock Snakepit in tests while using the real
  implementation in production.
  """

  @callback execute_in_session(
              session_id :: String.t(),
              tool_name :: String.t(),
              args :: map()
            ) :: {:ok, map()} | {:error, term()}

  @callback execute_in_session(
              session_id :: String.t(),
              tool_name :: String.t(),
              args :: map(),
              opts :: keyword()
            ) :: {:ok, map()} | {:error, term()}

  @callback get_stats() :: map()

  @doc """
  Execute a streaming tool, invoking callback for each chunk.
  """
  @callback execute_in_session_stream(
              session_id :: String.t(),
              tool_name :: String.t(),
              args :: map(),
              callback_fn :: (map() -> any()),
              opts :: keyword()
            ) :: :ok | {:error, term()}
end
