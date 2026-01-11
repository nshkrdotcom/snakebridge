defmodule SnakeBridge.RefInspectTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    restore = SnakeBridge.TestHelpers.put_runtime_client(SnakeBridge.RuntimeClientMock)
    on_exit(restore)

    :ok
  end

  test "inspect falls back when runtime call exits" do
    ref = %SnakeBridge.Ref{
      id: "ref-1",
      session_id: "session-1",
      python_module: "dspy",
      library: "dspy"
    }

    expect(SnakeBridge.RuntimeClientMock, :execute, 2, fn _tool, _payload, _opts ->
      exit(:noproc)
    end)

    assert inspect(ref) =~ "#SnakeBridge.Ref<ref-1>"
  end
end
