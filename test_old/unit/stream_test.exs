defmodule SnakeBridge.StreamTest do
  use ExUnit.Case, async: true

  test "from_callback yields streaming data chunks" do
    stream = SnakeBridge.Stream.from_callback("session_1", "call_python_stream", %{})

    assert Enum.to_list(stream) == ["Hello ", "from ", "mock!"]
  end
end
