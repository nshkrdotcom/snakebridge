defmodule Demo do
  require SnakeBridge

  @moduledoc """
  Affinity Defaults Example - Single Pool

  Demonstrates default affinity behavior (strict queue) and per-call overrides
  without multi-pool configuration.

  Run with: mix run --no-start -e Demo.run
  """

  alias SnakeBridge.Dynamic
  alias SnakeBridge.Examples
  alias SnakeBridge.SessionContext
  alias Snakepit.Bridge.SessionStore

  def run do
    SnakeBridge.script do
      Examples.reset_failures()

      IO.puts("Affinity Defaults Example: Single Pool")
      IO.puts(String.duplicate("=", 60))

      section("1. DEFAULT STRICT_QUEUE")
      demo_default_strict_queue()

      section("2. OVERRIDE TO HINT")
      demo_override_hint()

      section("3. OVERRIDE TO STRICT_FAIL_FAST")
      demo_override_fail_fast()

      IO.puts("")
      IO.puts(String.duplicate("=", 60))
      IO.puts("All demos completed - single pool affinity behaviors")

      Examples.assert_no_failures!()
    end
    |> Examples.assert_script_ok()
  end

  defp demo_default_strict_queue do
    IO.puts("Default affinity is strict_queue (configured in runtime.exs)")
    IO.puts("")

    session_id = "default_queue_#{System.unique_integer([:positive])}"

    {:ok, ref} =
      SessionContext.with_session([session_id: session_id], fn ->
        SnakeBridge.call("pathlib", "Path", ["/tmp/snake_default_queue"])
      end)

    preferred_worker = wait_for_worker_id(session_id, 25)
    IO.puts("  Preferred worker: #{preferred_worker || "unknown"}")

    sleep_task =
      Task.async(fn ->
        SessionContext.with_session([session_id: session_id], fn ->
          SnakeBridge.call("time", "sleep", [0.4])
        end)
      end)

    Process.sleep(40)

    {result, duration_ms} =
      timed(fn ->
        Dynamic.call(ref, :exists, [])
      end)

    current_worker = wait_for_worker_id(session_id, 10)
    IO.puts("  Call duration: #{duration_ms}ms")
    IO.puts("  Current worker: #{current_worker || "unknown"}")

    case result do
      {:ok, _} ->
        if preferred_worker && current_worker do
          IO.puts("  Stayed on preferred worker: #{preferred_worker == current_worker}")

          if preferred_worker != current_worker do
            Examples.record_failure()
          end
        end

      {:error, reason} ->
        IO.puts("  Unexpected error: #{inspect(reason)}")
        Examples.record_failure()
    end

    if duration_ms < 200 do
      IO.puts("  Completed quickly; contention may not have been observed")
    else
      IO.puts("  Waited for the busy worker (strict queue)")
    end

    _ = Task.await(sleep_task, 5_000)
    IO.puts("")
  end

  defp demo_override_hint do
    IO.puts("Override to hint should fall back when preferred worker is busy")
    IO.puts("")

    session_id = "override_hint_#{System.unique_integer([:positive])}"

    {:ok, ref} =
      SessionContext.with_session([session_id: session_id], fn ->
        SnakeBridge.call("pathlib", "Path", ["/tmp/snake_override_hint"])
      end)

    preferred_worker = wait_for_worker_id(session_id, 25)
    IO.puts("  Preferred worker: #{preferred_worker || "unknown"}")

    sleep_task =
      Task.async(fn ->
        SessionContext.with_session([session_id: session_id], fn ->
          SnakeBridge.call("time", "sleep", [0.4])
        end)
      end)

    Process.sleep(40)

    {result, duration_ms} =
      timed(fn ->
        Dynamic.call(ref, :exists, [], __runtime__: [affinity: :hint])
      end)

    current_worker = wait_for_worker_id(session_id, 10)
    IO.puts("  Call duration: #{duration_ms}ms")
    IO.puts("  Current worker: #{current_worker || "unknown"}")

    case result do
      {:error, _reason} ->
        IO.puts("  Hint override fell back; ref use failed as expected")

      {:ok, _} ->
        IO.puts("  Hint override stayed on preferred worker (no fallback observed)")

      other ->
        IO.puts("  Unexpected result: #{inspect(other)}")
        Examples.record_failure()
    end

    _ = Task.await(sleep_task, 5_000)
    IO.puts("")
  end

  defp demo_override_fail_fast do
    IO.puts("Override to strict_fail_fast returns :worker_busy when busy")
    IO.puts("")

    session_id = "override_fail_fast_#{System.unique_integer([:positive])}"

    {:ok, ref} =
      SessionContext.with_session([session_id: session_id], fn ->
        SnakeBridge.call("pathlib", "Path", ["/tmp/snake_override_fail_fast"])
      end)

    preferred_worker = wait_for_worker_id(session_id, 25)
    IO.puts("  Preferred worker: #{preferred_worker || "unknown"}")

    sleep_task =
      Task.async(fn ->
        SessionContext.with_session([session_id: session_id], fn ->
          SnakeBridge.call("time", "sleep", [0.4])
        end)
      end)

    Process.sleep(40)

    {result, duration_ms} =
      timed(fn ->
        Dynamic.call(ref, :exists, [], __runtime__: [affinity: :strict_fail_fast])
      end)

    current_worker = wait_for_worker_id(session_id, 10)
    IO.puts("  Call duration: #{duration_ms}ms")
    IO.puts("  Current worker: #{current_worker || "unknown"}")

    case result do
      {:error, :worker_busy} ->
        IO.puts("  Strict fail-fast returned :worker_busy as expected")

      {:ok, _} ->
        IO.puts("  Strict fail-fast succeeded; no contention observed")

      {:error, reason} ->
        IO.puts("  Unexpected error: #{inspect(reason)}")
        Examples.record_failure()
    end

    _ = Task.await(sleep_task, 5_000)
    IO.puts("")
  end

  defp wait_for_worker_id(session_id, attempts) when attempts > 0 do
    case SessionStore.get_session(session_id) do
      {:ok, %{last_worker_id: worker_id}} when is_binary(worker_id) ->
        worker_id

      _ ->
        Process.sleep(25)
        wait_for_worker_id(session_id, attempts - 1)
    end
  end

  defp wait_for_worker_id(_session_id, _attempts), do: nil

  defp timed(fun) when is_function(fun, 0) do
    start_ms = System.monotonic_time(:millisecond)
    result = fun.()
    duration_ms = System.monotonic_time(:millisecond) - start_ms
    {result, duration_ms}
  end

  defp section(title) do
    IO.puts("")
    IO.puts(String.duplicate("-", 60))
    IO.puts(title)
    IO.puts(String.duplicate("-", 60))
    IO.puts("")
  end
end
