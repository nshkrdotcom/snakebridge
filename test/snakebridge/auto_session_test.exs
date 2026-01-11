defmodule SnakeBridge.AutoSessionTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    restore = SnakeBridge.TestHelpers.put_runtime_client(SnakeBridge.RuntimeClientMock)
    on_exit(restore)

    # Clear any existing auto-session
    SnakeBridge.Runtime.clear_auto_session()

    :ok
  end

  describe "auto session creation" do
    test "creates session on first Python call" do
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, _opts ->
        # Verify session_id is present and starts with "auto_"
        assert Map.has_key?(payload, "session_id")
        assert String.starts_with?(payload["session_id"], "auto_")
        {:ok, 2.0}
      end)

      assert Process.get(:snakebridge_auto_session) == nil
      {:ok, _} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [4])
      session_id = Process.get(:snakebridge_auto_session)
      assert session_id != nil
      assert String.starts_with?(session_id, "auto_")
    end

    test "reuses session for subsequent calls" do
      expect(SnakeBridge.RuntimeClientMock, :execute, 2, fn "snakebridge.call", payload, _opts ->
        send(self(), {:session_id, payload["session_id"]})
        {:ok, 2.0}
      end)

      {:ok, _} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [4])
      {:ok, _} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [9])

      # Collect session_ids
      assert_receive {:session_id, session_1}
      assert_receive {:session_id, session_2}

      assert session_1 == session_2
    end

    test "explicit session overrides auto-session" do
      # First call with auto-session
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, _opts ->
        send(self(), {:auto_session, payload["session_id"]})
        {:ok, 2.0}
      end)

      {:ok, _} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [4])
      assert_receive {:auto_session, auto_session}

      # Call within explicit session
      explicit =
        SnakeBridge.SessionContext.with_session([session_id: "explicit_123"], fn ->
          SnakeBridge.Runtime.current_session()
        end)

      assert explicit == "explicit_123"

      # After with_session, back to auto
      assert SnakeBridge.Runtime.current_session() == auto_session
    end

    test "auto-session ID contains PID and timestamp" do
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", _payload, _opts ->
        {:ok, 2.0}
      end)

      {:ok, _} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [4])
      session_id = SnakeBridge.Runtime.current_session()

      assert String.starts_with?(session_id, "auto_")
      # PID format is like <0.123.0>
      assert String.contains?(session_id, "<")
      assert String.contains?(session_id, ">")
      # Contains an underscore separator before timestamp
      parts = String.split(session_id, "_")
      assert length(parts) >= 2
    end
  end

  describe "process isolation" do
    test "different processes get different sessions" do
      # Allow calls from multiple processes
      stub(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", _payload, _opts ->
        {:ok, 2.0}
      end)

      {:ok, _} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [4])
      session_1 = SnakeBridge.Runtime.current_session()

      session_2 =
        Task.async(fn ->
          SnakeBridge.TestHelpers.with_runtime_client(SnakeBridge.RuntimeClientMock, fn ->
            {:ok, _} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [9])
            SnakeBridge.Runtime.current_session()
          end)
        end)
        |> Task.await()

      assert session_1 != session_2
    end

    test "parallel processes each get unique sessions" do
      stub(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", _payload, _opts ->
        {:ok, 2.0}
      end)

      tasks =
        for _ <- 1..5 do
          Task.async(fn ->
            SnakeBridge.TestHelpers.with_runtime_client(SnakeBridge.RuntimeClientMock, fn ->
              {:ok, _} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [4])
              SnakeBridge.Runtime.current_session()
            end)
          end)
        end

      sessions = Task.await_many(tasks)
      unique_sessions = Enum.uniq(sessions)

      assert length(unique_sessions) == 5
    end
  end

  describe "session cleanup" do
    test "clear_auto_session removes from process dictionary" do
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", _payload, _opts ->
        {:ok, 2.0}
      end)

      {:ok, _} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [4])
      assert Process.get(:snakebridge_auto_session) != nil
      SnakeBridge.Runtime.clear_auto_session()
      assert Process.get(:snakebridge_auto_session) == nil
    end

    test "clear_auto_session returns :ok" do
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", _payload, _opts ->
        {:ok, 2.0}
      end)

      {:ok, _} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [4])
      assert :ok = SnakeBridge.Runtime.clear_auto_session()
    end

    test "clear_auto_session is idempotent" do
      assert :ok = SnakeBridge.Runtime.clear_auto_session()
      assert :ok = SnakeBridge.Runtime.clear_auto_session()
    end

    test "release_auto_session creates new session on next call" do
      # First call creates session, then release creates a new one on second call
      expect(SnakeBridge.RuntimeClientMock, :execute, 3, fn action, _payload, _opts ->
        case action do
          "snakebridge.call" -> {:ok, 2.0}
          "snakebridge.release_session" -> {:ok, :released}
        end
      end)

      {:ok, _} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [4])
      old = SnakeBridge.Runtime.current_session()
      :ok = SnakeBridge.Runtime.release_auto_session()

      # Ensure process dictionary is cleared
      assert Process.get(:snakebridge_auto_session) == nil

      # Minimal delay to ensure timestamp differs for new session ID
      # This is required because session IDs include monotonic time
      :timer.sleep(1)

      {:ok, _} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [9])
      new = SnakeBridge.Runtime.current_session()
      assert old != new
    end

    test "release_auto_session clears process dictionary" do
      expect(SnakeBridge.RuntimeClientMock, :execute, 2, fn action, _payload, _opts ->
        case action do
          "snakebridge.call" -> {:ok, 2.0}
          "snakebridge.release_session" -> {:ok, :released}
        end
      end)

      {:ok, _} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [4])
      assert Process.get(:snakebridge_auto_session) != nil
      :ok = SnakeBridge.Runtime.release_auto_session()
      assert Process.get(:snakebridge_auto_session) == nil
    end

    test "release_auto_session returns :ok when no session" do
      assert :ok = SnakeBridge.Runtime.release_auto_session()
    end
  end

  describe "session manager integration" do
    test "auto-session is registered with SessionManager" do
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", _payload, _opts ->
        {:ok, 2.0}
      end)

      {:ok, _} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [4])
      session_id = SnakeBridge.Runtime.current_session()

      assert SnakeBridge.SessionManager.session_exists?(session_id)
    end

    test "release_auto_session unregisters from SessionManager" do
      expect(SnakeBridge.RuntimeClientMock, :execute, 2, fn action, _payload, _opts ->
        case action do
          "snakebridge.call" -> {:ok, 2.0}
          "snakebridge.release_session" -> {:ok, :released}
        end
      end)

      {:ok, _} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [4])
      session_id = SnakeBridge.Runtime.current_session()

      assert SnakeBridge.SessionManager.session_exists?(session_id)
      :ok = SnakeBridge.Runtime.release_auto_session()
      refute SnakeBridge.SessionManager.session_exists?(session_id)
    end

    test "SessionManager tracks session state" do
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", _payload, _opts ->
        {:ok, 2.0}
      end)

      {:ok, _} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [4])
      session_id = SnakeBridge.Runtime.current_session()

      state = :sys.get_state(SnakeBridge.SessionManager)
      assert Map.has_key?(state.sessions, session_id)
      session_data = state.sessions[session_id]
      assert Map.has_key?(session_data.owners, self())
    end
  end

  describe "session wire format" do
    test "session_id always present in current_session" do
      # Without calling Python, current_session still generates an auto-session
      session_id = SnakeBridge.Runtime.current_session()
      assert is_binary(session_id)
      assert String.starts_with?(session_id, "auto_")
    end

    test "call_dynamic includes session_id in payload" do
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, _opts ->
        assert Map.has_key?(payload, "session_id")
        assert is_binary(payload["session_id"])
        assert String.starts_with?(payload["session_id"], "auto_")
        {:ok, 2.0}
      end)

      {:ok, _} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [4])
    end
  end
end
