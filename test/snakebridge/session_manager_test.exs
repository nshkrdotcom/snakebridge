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
      test_pid = self()

      owner =
        spawn(fn ->
          SnakeBridge.SessionManager.register_session(session_id, self())
          send(test_pid, :session_registered)

          receive do
            :stop -> :ok
          end
        end)

      # Wait for session registration
      assert_receive :session_registered, 1000
      assert SnakeBridge.SessionManager.session_exists?(session_id)

      # Kill owner and wait for process to die
      ref = Process.monitor(owner)
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^ref, :process, ^owner, :killed}, 1000

      # Wait for session cleanup using eventually
      assert SnakeBridge.TestHelpers.eventually(
               fn -> not SnakeBridge.SessionManager.session_exists?(session_id) end,
               timeout: 1000
             )
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
