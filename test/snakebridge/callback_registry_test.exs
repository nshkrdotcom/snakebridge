defmodule SnakeBridge.CallbackRegistryTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.Runtime
  alias Snakepit.Bridge.ToolRegistry

  setup do
    Runtime.clear_auto_session()
    SnakeBridge.SessionContext.clear_current()

    start_if_needed(Snakepit.Bridge.ToolRegistry)
    start_if_needed(SnakeBridge.CallbackRegistry)

    :ok
  end

  test "registers callback tool under the current auto session" do
    session_id = Runtime.current_session()

    _encoded = SnakeBridge.Types.encode(fn -> :ok end)

    tools = ToolRegistry.list_exposed_elixir_tools(session_id)
    assert Enum.any?(tools, &(&1.name == "snakebridge.callback"))
  end

  defp start_if_needed(module) do
    case Process.whereis(module) do
      nil ->
        {:ok, _pid} = start_supervised({module, []})
        :ok

      _pid ->
        :ok
    end
  end
end
