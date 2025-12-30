defmodule SnakeBridge.SessionManagerTest do
  use ExUnit.Case

  describe "session lifecycle" do
    test "session registered on first call" do
      session_id = "test_session_#{System.unique_integer()}"

      :ok = SnakeBridge.SessionManager.register_session(session_id, self())

      assert SnakeBridge.SessionManager.session_exists?(session_id)
    end

    test "session released when owner process dies" do
      session_id = "test_session_#{System.unique_integer()}"

      owner =
        spawn(fn ->
          SnakeBridge.SessionManager.register_session(session_id, self())

          receive do
            :stop -> :ok
          end
        end)

      Process.sleep(50)
      assert SnakeBridge.SessionManager.session_exists?(session_id)

      Process.exit(owner, :kill)
      Process.sleep(100)

      refute SnakeBridge.SessionManager.session_exists?(session_id)
    end

    test "refs tracked per session" do
      session_id = "test_session_#{System.unique_integer()}"
      :ok = SnakeBridge.SessionManager.register_session(session_id, self())

      ref1 = %{"id" => "ref1", "session_id" => session_id}
      ref2 = %{"id" => "ref2", "session_id" => session_id}

      :ok = SnakeBridge.SessionManager.register_ref(session_id, ref1)
      :ok = SnakeBridge.SessionManager.register_ref(session_id, ref2)

      refs = SnakeBridge.SessionManager.list_refs(session_id)
      assert length(refs) == 2
    end
  end
end
