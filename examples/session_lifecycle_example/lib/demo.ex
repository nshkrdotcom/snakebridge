defmodule Demo do
  @moduledoc """
  Session Lifecycle Example - Demonstrates session management in SnakeBridge.

  Shows:
  - Explicit sessions with SessionContext.with_session/1
  - Auto-sessions (NEW in v0.8.4)
  - Session cleanup and isolation

  Run with: mix run --no-start -e Demo.run
  """

  alias SnakeBridge.Dynamic
  alias SnakeBridge.Examples
  alias SnakeBridge.Runtime
  alias SnakeBridge.SessionContext
  alias SnakeBridge.SessionManager

  def run do
    SnakeBridge.run_as_script(fn ->
      Examples.reset_failures()

      IO.puts("Session Lifecycle Example")
      IO.puts(String.duplicate("=", 50))

      # Original session features
      section("EXPLICIT SESSIONS")
      step("Session-scoped auto-ref")
      session_scoped_refs()

      step("Session released when owner exits")
      owner_exit_cleanup()

      step("Manual session release")
      manual_release()

      # New v0.8.4 auto-session features
      section("AUTO-SESSIONS (NEW in v0.8.4)")
      step("Auto-session creation on first call")
      demo_auto_session()

      step("Session release and recreation")
      demo_session_release()

      step("Process isolation")
      demo_process_isolation()

      step("Auto vs explicit sessions")
      demo_session_comparison()

      IO.puts("")
      IO.puts(String.duplicate("=", 50))
      IO.puts("All demos completed!")

      Examples.assert_no_failures!()
    end)
    |> Examples.assert_script_ok()
  end

  # ============================================================================
  # Original Session Features
  # ============================================================================

  defp session_scoped_refs do
    SessionContext.with_session(fn ->
      context = SessionContext.current()
      IO.puts("Session ID: #{context.session_id}")

      ref1 = fetch_ref(".")
      ref2 = fetch_ref("..")

      if is_map(ref1) and is_map(ref2) do
        IO.puts("Ref1 session: #{Map.get(ref1, "session_id")}")
        IO.puts("Ref2 session: #{Map.get(ref2, "session_id")}")

        print_result("ref1.exists()", Dynamic.call(ref1, :exists, []))
        print_result("ref2.exists()", Dynamic.call(ref2, :exists, []))
      end
    end)
  end

  defp owner_exit_cleanup do
    parent = self()

    owner =
      spawn(fn ->
        SessionContext.with_session(fn ->
          context = SessionContext.current()
          send(parent, {:session_id, context.session_id})

          case Runtime.call_dynamic("pathlib", "Path", ["."]) do
            {:ok, ref} -> send(parent, {:ref, ref})
            other -> send(parent, {:ref_error, other})
          end

          receive do
            :stop -> :ok
          end
        end)
      end)

    session_id =
      receive do
        {:session_id, id} -> id
      after
        1000 -> nil
      end

    if is_binary(session_id) do
      Process.sleep(50)
      IO.puts("Session exists? #{SessionManager.session_exists?(session_id)}")

      Process.exit(owner, :kill)
      Process.sleep(100)

      IO.puts("Session exists after owner exit? #{SessionManager.session_exists?(session_id)}")
    else
      IO.puts("Failed to capture session id")
      Examples.record_failure()
    end
  end

  defp manual_release do
    session_id =
      SessionContext.with_session(fn ->
        context = SessionContext.current()

        case Runtime.call_dynamic("pathlib", "Path", ["."]) do
          {:ok, ref} ->
            assert_ref(ref)
            print_result("path.name", Dynamic.get_attr(ref, :name))

          other ->
            print_result("Path creation", other)
        end

        context.session_id
      end)

    :ok = SessionManager.release_session(session_id)
    IO.puts("Released session: #{session_id}")
    IO.puts("Session exists after release? #{SessionManager.session_exists?(session_id)}")
  end

  # ============================================================================
  # New v0.8.4 Auto-Session Features
  # ============================================================================

  defp demo_auto_session do
    # Clear any existing auto-session for clean demo
    Runtime.clear_auto_session()

    IO.puts("Before first call: no session yet")

    # First Python call creates auto-session
    {:ok, _} = SnakeBridge.call("math", "sqrt", [16])

    # Check current session
    session_id = SnakeBridge.current_session()
    IO.puts("Auto-session ID: #{session_id}")
    IO.puts("Starts with 'auto_': #{String.starts_with?(session_id, "auto_")}")

    # Subsequent calls reuse the same session
    {:ok, _} = SnakeBridge.call("math", "sqrt", [25])
    same_session = SnakeBridge.current_session()
    IO.puts("Same session after second call: #{session_id == same_session}")

    # Refs are automatically scoped to this session
    {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])

    if SnakeBridge.ref?(ref) do
      IO.puts("Ref session matches auto-session: #{ref.session_id == session_id}")
    else
      IO.puts("Got ref: #{inspect(ref)}")
    end
  end

  defp demo_session_release do
    # Ensure we have an auto-session
    Runtime.clear_auto_session()
    {:ok, _} = SnakeBridge.call("math", "sqrt", [16])
    old_session = SnakeBridge.current_session()
    IO.puts("Current session: #{old_session}")

    # Release the session
    :ok = SnakeBridge.release_auto_session()
    IO.puts("Session released")

    # Next call creates new session
    {:ok, _} = SnakeBridge.call("math", "sqrt", [25])
    new_session = SnakeBridge.current_session()
    IO.puts("New session: #{new_session}")
    IO.puts("Sessions different: #{old_session != new_session}")
  end

  defp demo_process_isolation do
    # Ensure clean state
    Runtime.clear_auto_session()

    # Get session in main process
    {:ok, _} = SnakeBridge.call("math", "sqrt", [16])
    main_session = SnakeBridge.current_session()
    IO.puts("Main process session: #{main_session}")

    # Spawn task - gets different session
    task_session =
      Task.async(fn ->
        {:ok, _} = SnakeBridge.call("math", "sqrt", [25])
        SnakeBridge.current_session()
      end)
      |> Task.await()

    IO.puts("Task process session: #{task_session}")
    IO.puts("Sessions isolated: #{main_session != task_session}")
  end

  defp demo_session_comparison do
    # Ensure clean state
    Runtime.clear_auto_session()

    IO.puts("")
    IO.puts("Auto-session (v0.8.4+ default):")
    {:ok, _} = SnakeBridge.call("math", "sqrt", [16])
    auto = SnakeBridge.current_session()
    IO.puts("  Session: #{auto}")
    IO.puts("  Auto-generated: #{String.starts_with?(auto, "auto_")}")

    IO.puts("")
    IO.puts("Explicit session (still works, overrides auto):")

    explicit_id =
      SessionContext.with_session([session_id: "my_explicit_session"], fn ->
        SnakeBridge.current_session()
      end)

    IO.puts("  Session: #{explicit_id}")
    IO.puts("  User-defined: #{explicit_id == "my_explicit_session"}")

    IO.puts("")
    IO.puts("After with_session block:")
    back_to_auto = SnakeBridge.current_session()
    IO.puts("  Back to auto: #{back_to_auto == auto}")
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp section(title) do
    IO.puts("")
    IO.puts(String.duplicate("-", 50))
    IO.puts(title)
    IO.puts(String.duplicate("-", 50))
  end

  defp step(title) do
    IO.puts("")
    IO.puts("== #{title} ==")
  end

  defp fetch_ref(path) do
    case Runtime.call_dynamic("pathlib", "Path", [path]) do
      {:ok, ref} ->
        assert_ref(ref)
        ref

      other ->
        print_result("Path creation", other)
        Examples.record_failure()
        nil
    end
  end

  defp assert_ref(ref) do
    if Dynamic.ref?(ref) do
      :ok
    else
      IO.puts("Expected a ref, got: #{inspect(ref)}")
      Examples.record_failure()
    end
  end

  defp print_result(label, {:ok, value}) do
    IO.puts("#{label} = {:ok, #{inspect(value)}}")
  end

  defp print_result(label, {:error, reason}) do
    IO.puts("#{label} = {:error, #{inspect(reason)}}")
    Examples.record_failure()
  end

  defp print_result(label, other) do
    IO.puts("#{label} = #{inspect(other)}")
  end
end
