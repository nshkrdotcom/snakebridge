defmodule SnakeBridge.SessionIdTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.SessionId

  test "generates unique, prefixed session ids" do
    id1 = SessionId.generate("test")
    id2 = SessionId.generate("test")

    assert id1 != id2
    assert String.starts_with?(id1, "test_")
    assert String.starts_with?(id2, "test_")
  end
end
