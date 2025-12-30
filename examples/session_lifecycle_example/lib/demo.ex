defmodule Demo do
  @moduledoc """
  Run with: mix run -e Demo.run
  """

  alias SnakeBridge.Dynamic
  alias SnakeBridge.Examples
  alias SnakeBridge.Runtime
  alias SnakeBridge.SessionContext
  alias SnakeBridge.SessionManager

  def run do
    Snakepit.run_as_script(fn ->
      Examples.reset_failures()

      IO.puts("Session Lifecycle Example")
      IO.puts("------------------------")

      step("Session-scoped auto-ref")
      session_scoped_refs()

      step("Session released when owner exits")
      owner_exit_cleanup()

      step("Manual session release")
      manual_release()

      Examples.assert_no_failures!()
    end)
    |> Examples.assert_script_ok()
  end

  defp session_scoped_refs do
    SessionContext.with_session(fn ->
      context = SessionContext.current()
      IO.puts("Session ID: #{context.session_id}")

      ref1 = fetch_ref(".")
      ref2 = fetch_ref("..")

      if is_map(ref1) and is_map(ref2) do
        IO.puts("Ref1 session: #{Map.get(ref1, "session_id")}")
        IO.puts("Ref2 session: #{Map.get(ref2, "session_id")}")

        print_result(Dynamic.call(ref1, :exists, []))
        print_result(Dynamic.call(ref2, :exists, []))
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
            print_result(Dynamic.get_attr(ref, :name))

          other ->
            print_result(other)
        end

        context.session_id
      end)

    :ok = SessionManager.release_session(session_id)
    IO.puts("Released session: #{session_id}")
    IO.puts("Session exists after release? #{SessionManager.session_exists?(session_id)}")
  end

  defp fetch_ref(path) do
    case Runtime.call_dynamic("pathlib", "Path", [path]) do
      {:ok, ref} ->
        assert_ref(ref)
        ref

      other ->
        print_result(other)
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

  defp step(title) do
    IO.puts("")
    IO.puts("== #{title} ==")
  end

  defp print_result({:ok, value}) do
    IO.puts("Result: {:ok, #{inspect(value)}}")
  end

  defp print_result({:error, reason}) do
    IO.puts("Result: {:error, #{inspect(reason)}}")
    Examples.record_failure()
  end

  defp print_result(other) do
    IO.puts("Result: #{inspect(other)}")
  end
end
