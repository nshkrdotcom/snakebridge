defmodule Demo do
  @moduledoc """
  Multi-Session Example - Multiple Snakes in the Pit!

  Demonstrates running multiple isolated Python sessions concurrently.
  Each session maintains independent state - objects created in one session
  are invisible to others.

  Use cases:
  - Multi-tenant applications (each tenant gets isolated Python state)
  - Parallel processing with isolated state per worker
  - A/B testing different configurations side-by-side
  - Resource isolation (separate memory pools per session)
  - Affinity mode tuning for stateful refs under load
  - Per-call affinity overrides and auto-session behavior
  - Streaming calls that depend on session-bound refs
  - Handling tainted/unavailable preferred workers

  Run with: mix run --no-start -e Demo.run
  """

  alias SnakeBridge.Dynamic
  alias SnakeBridge.Examples
  alias SnakeBridge.Runtime
  alias SnakeBridge.SessionContext
  alias Snakepit.Bridge.SessionStore
  alias Snakepit.Worker.TaintRegistry

  @affinity_pools [
    %{label: "hint", pool: :hint_pool},
    %{label: "strict_queue", pool: :strict_queue_pool},
    %{label: "strict_fail_fast", pool: :strict_fail_fast_pool}
  ]

  def run do
    SnakeBridge.run_as_script(fn ->
      Examples.reset_failures()

      IO.puts("Multi-Session Example: Multiple Snakes in the Pit!")
      IO.puts(String.duplicate("=", 60))

      section("1. CONCURRENT ISOLATED SESSIONS")
      demo_concurrent_sessions()

      section("2. SESSION STATE ISOLATION")
      demo_state_isolation()

      section("3. AFFINITY MODES UNDER LOAD")
      demo_affinity_modes()

      section("4. AFFINITY OVERRIDES + AUTO-SESSIONS")
      demo_affinity_overrides()
      demo_auto_sessions()

      section("5. AFFINITY EDGE CASES (TAINTED WORKER)")
      demo_affinity_unavailable()

      section("6. STREAMING WITH AFFINITY")
      demo_streaming_affinity()

      section("7. NAMED SESSIONS FOR REUSE")
      demo_named_sessions()

      section("8. PARALLEL PROCESSING PATTERN")
      demo_parallel_processing()

      IO.puts("")
      IO.puts(String.duplicate("=", 60))
      IO.puts("All demos completed - multiple snakes, one pit!")

      Examples.assert_no_failures!()
    end)
    |> Examples.assert_script_ok()
  end

  # ============================================================================
  # Demo 1: Concurrent Isolated Sessions
  # ============================================================================

  defp demo_concurrent_sessions do
    IO.puts("Running two sessions concurrently, each building different JSON...")
    IO.puts("")

    # Warm up the connection on main process first
    {:ok, _} = SnakeBridge.call("json", "dumps", [%{warmup: true}])

    tasks = [
      Task.async(fn ->
        SessionContext.with_session([session_id: "snake_alpha"], fn ->
          session = SnakeBridge.current_session()
          {:ok, data} = SnakeBridge.call("json", "dumps", [%{snake: "alpha", value: 100}])
          {:alpha, session, data}
        end)
      end),
      Task.async(fn ->
        SessionContext.with_session([session_id: "snake_beta"], fn ->
          session = SnakeBridge.current_session()
          {:ok, data} = SnakeBridge.call("json", "dumps", [%{snake: "beta", value: 200}])
          {:beta, session, data}
        end)
      end)
    ]

    results = Task.await_many(tasks)

    Enum.each(results, fn {name, session, data} ->
      IO.puts("  Session '#{session}' (#{name}): #{data}")
    end)

    # Verify they were different sessions
    [{:alpha, session_a, _}, {:beta, session_b, _}] = results

    if session_a != session_b do
      IO.puts("")
      IO.puts("  Sessions isolated: #{session_a} != #{session_b}")
    else
      IO.puts("  ERROR: Sessions should be different!")
      Examples.record_failure()
    end
  end

  # ============================================================================
  # Demo 2: Session State Isolation
  # ============================================================================

  defp demo_state_isolation do
    IO.puts("Creating Path objects in separate sessions...")
    IO.puts("")

    # Session A creates a Path object
    {ref_a, session_a} =
      SessionContext.with_session([session_id: "session_a"], fn ->
        {:ok, ref} = Runtime.call_dynamic("pathlib", "Path", ["/tmp/snake_a"])
        session = SnakeBridge.current_session()
        IO.puts("  Session A (#{session}) created Path: /tmp/snake_a")
        {ref, session}
      end)

    # Session B creates a different Path object
    {ref_b, session_b} =
      SessionContext.with_session([session_id: "session_b"], fn ->
        {:ok, ref} = Runtime.call_dynamic("pathlib", "Path", ["/tmp/snake_b"])
        session = SnakeBridge.current_session()
        IO.puts("  Session B (#{session}) created Path: /tmp/snake_b")
        {ref, session}
      end)

    # Verify isolation
    IO.puts("")
    IO.puts("  Ref A belongs to session: #{ref_a.session_id}")
    IO.puts("  Ref B belongs to session: #{ref_b.session_id}")

    if ref_a.session_id == session_a and ref_b.session_id == session_b do
      IO.puts("  Refs correctly scoped to their sessions")
    else
      IO.puts("  ERROR: Refs not properly scoped!")
      Examples.record_failure()
    end

    if ref_a.session_id != ref_b.session_id do
      IO.puts("  Sessions fully isolated")
    else
      IO.puts("  ERROR: Sessions should be different!")
      Examples.record_failure()
    end
  end

  # ============================================================================
  # Demo 3: Affinity Modes Under Load
  # ============================================================================

  defp demo_affinity_modes do
    IO.puts("Demonstrating hint vs strict affinity with a busy preferred worker...")
    IO.puts("")

    Enum.each(@affinity_pools, fn %{label: label, pool: pool_name} ->
      demo_affinity_mode(label, pool_name)
    end)
  end

  defp demo_affinity_mode(label, pool_name) do
    session_id = "affinity_#{label}_#{System.unique_integer([:positive])}"

    IO.puts("Mode: #{label} (pool: #{pool_name})")

    {:ok, ref} =
      SessionContext.with_session([session_id: session_id], fn ->
        SnakeBridge.call("pathlib", "Path", ["/tmp/snake_affinity_#{label}"],
          __runtime__: [pool_name: pool_name]
        )
      end)

    preferred_worker = wait_for_worker_id(session_id, 25)
    IO.puts("  Preferred worker: #{preferred_worker || "unknown"}")

    sleep_task =
      Task.async(fn ->
        SessionContext.with_session([session_id: session_id], fn ->
          SnakeBridge.call("time", "sleep", [0.4], __runtime__: [pool_name: pool_name])
        end)
      end)

    Process.sleep(40)

    {result, duration_ms} =
      timed(fn ->
        Dynamic.call(ref, :exists, [], __runtime__: [pool_name: pool_name])
      end)

    current_worker = wait_for_worker_id(session_id, 10)
    IO.puts("  Call duration: #{duration_ms}ms")
    IO.puts("  Current worker: #{current_worker || "unknown"}")

    case {label, result} do
      {"hint", {:error, _reason}} ->
        IO.puts("  Hint mode fell back; ref use failed as expected")

      {"hint", {:ok, _}} ->
        IO.puts("  Hint mode stayed on preferred worker; no fallback observed")

      {"strict_queue", {:ok, _}} ->
        if preferred_worker && current_worker do
          IO.puts(
            "  Strict queue waited for preferred worker: #{preferred_worker == current_worker}"
          )

          if preferred_worker != current_worker do
            IO.puts("  Unexpected worker change; check affinity config")
            Examples.record_failure()
          end
        else
          IO.puts("  Strict queue completed; worker check unavailable")
        end

      {"strict_fail_fast", {:error, :worker_busy}} ->
        IO.puts("  Strict fail-fast returned :worker_busy while preferred worker was busy")

      {"strict_fail_fast", {:error, :session_worker_unavailable}} ->
        IO.puts("  Strict fail-fast returned :session_worker_unavailable")

      {"strict_fail_fast", {:ok, _}} ->
        IO.puts(
          "  Strict fail-fast succeeded; no contention observed (re-run to see :worker_busy)"
        )

      _ ->
        IO.puts("  Unexpected result: #{inspect(result)}")
        Examples.record_failure()
    end

    _ = Task.await(sleep_task, 5_000)
    IO.puts("")
  end

  # ============================================================================
  # Demo 4: Affinity Overrides + Auto-Session Behavior
  # ============================================================================

  defp demo_affinity_overrides do
    IO.puts("Per-call overrides can change strictness for the same pool...")
    IO.puts("")

    demo_affinity_override(
      "strict_queue -> hint",
      :strict_queue_pool,
      :hint
    )

    demo_affinity_override(
      "strict_fail_fast -> strict_queue",
      :strict_fail_fast_pool,
      :strict_queue
    )
  end

  defp demo_affinity_override(label, pool_name, override_affinity) do
    label_slug = "#{pool_name}_#{override_affinity}"
    session_id = "override_#{label_slug}_#{System.unique_integer([:positive])}"

    IO.puts("Override: #{label} (pool: #{pool_name})")

    {:ok, ref} =
      SessionContext.with_session([session_id: session_id], fn ->
        SnakeBridge.call("pathlib", "Path", ["/tmp/snake_override_#{label_slug}"],
          __runtime__: [pool_name: pool_name]
        )
      end)

    preferred_worker = wait_for_worker_id(session_id, 25)
    IO.puts("  Preferred worker: #{preferred_worker || "unknown"}")

    sleep_task =
      Task.async(fn ->
        SessionContext.with_session([session_id: session_id], fn ->
          SnakeBridge.call("time", "sleep", [0.4], __runtime__: [pool_name: pool_name])
        end)
      end)

    Process.sleep(40)

    {result, duration_ms} =
      timed(fn ->
        Dynamic.call(ref, :exists, [],
          __runtime__: [pool_name: pool_name, affinity: override_affinity]
        )
      end)

    current_worker = wait_for_worker_id(session_id, 10)
    IO.puts("  Call duration: #{duration_ms}ms")
    IO.puts("  Current worker: #{current_worker || "unknown"}")

    case {override_affinity, result} do
      {:hint, {:error, _reason}} ->
        IO.puts("  Override to hint fell back; ref use failed as expected")

      {:hint, {:ok, _}} ->
        IO.puts("  Override to hint stayed on preferred worker (no fallback observed)")

      {:strict_queue, {:ok, _}} ->
        if preferred_worker && current_worker do
          IO.puts("  Override to strict_queue waited: #{preferred_worker == current_worker}")
        else
          IO.puts("  Override to strict_queue completed; worker check unavailable")
        end

      {:strict_queue, {:error, reason}} ->
        IO.puts("  Override to strict_queue returned error: #{inspect(reason)}")
        Examples.record_failure()

      _ ->
        IO.puts("  Unexpected override result: #{inspect(result)}")
        Examples.record_failure()
    end

    _ = Task.await(sleep_task, 5_000)
    IO.puts("")
  end

  defp demo_auto_sessions do
    IO.puts("Auto-sessions are process-scoped and still benefit from affinity...")
    IO.puts("")

    :ok = Runtime.clear_auto_session()
    auto_session = SnakeBridge.current_session()

    {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["/tmp/snake_auto_session"])
    IO.puts("  Auto session: #{auto_session}")
    IO.puts("  Ref session:  #{ref.session_id}")

    if ref.session_id == auto_session do
      IO.puts("  Auto-session IDs are stable per process")
    else
      IO.puts("  ERROR: Auto-session ID mismatch")
      Examples.record_failure()
    end

    :ok = Runtime.clear_auto_session()
    new_session = SnakeBridge.current_session()

    if new_session != auto_session do
      IO.puts("  Clearing auto-session creates a new session: #{new_session}")
    else
      IO.puts("  ERROR: Auto-session did not change after clear")
      Examples.record_failure()
    end

    IO.puts("")
  end

  # ============================================================================
  # Demo 5: Affinity Edge Cases (Tainted Worker)
  # ============================================================================

  defp demo_affinity_unavailable do
    IO.puts("Simulating a tainted preferred worker to show :session_worker_unavailable...")
    IO.puts("")

    pool_name = :strict_fail_fast_pool
    session_id = "taint_#{System.unique_integer([:positive])}"

    {:ok, ref} =
      SessionContext.with_session([session_id: session_id], fn ->
        SnakeBridge.call("pathlib", "Path", ["/tmp/snake_taint_demo"],
          __runtime__: [pool_name: pool_name]
        )
      end)

    preferred_worker = wait_for_worker_id(session_id, 25)
    IO.puts("  Preferred worker: #{preferred_worker || "unknown"}")

    if preferred_worker do
      :ok =
        TaintRegistry.taint_worker(preferred_worker,
          duration_ms: 5_000,
          reason: :demo
        )

      result =
        Dynamic.call(ref, :exists, [], __runtime__: [pool_name: pool_name])

      case result do
        {:error, :session_worker_unavailable} ->
          IO.puts("  Got :session_worker_unavailable as expected")

        {:error, other} ->
          IO.puts("  Unexpected error: #{inspect(other)}")
          Examples.record_failure()

        {:ok, _} ->
          IO.puts("  Unexpected success while worker tainted")
          Examples.record_failure()
      end

      :ok = TaintRegistry.clear_worker(preferred_worker)
    else
      IO.puts("  Skipping taint demo: preferred worker not found")
      Examples.record_failure()
    end

    IO.puts("")
  end

  # ============================================================================
  # Demo 6: Streaming With Affinity
  # ============================================================================

  defp demo_streaming_affinity do
    IO.puts("Streaming honors affinity when a session ref is involved...")
    IO.puts("")

    demo_streaming_mode("strict_queue", :strict_queue_pool, :strict_queue, false)
    demo_streaming_mode("hint", :hint_pool, :hint, true)
  end

  defp demo_streaming_mode(label, pool_name, affinity, contend?) do
    session_id = "stream_#{label}_#{System.unique_integer([:positive])}"
    IO.puts("Mode: #{label} (pool: #{pool_name})")

    {:ok, ref} =
      SessionContext.with_session([session_id: session_id], fn ->
        SnakeBridge.call("pathlib", "Path", ["/tmp/snake_stream_#{label}"],
          __runtime__: [pool_name: pool_name]
        )
      end)

    preferred_worker = wait_for_worker_id(session_id, 25)
    IO.puts("  Preferred worker: #{preferred_worker || "unknown"}")

    sleep_task =
      if contend? do
        Task.async(fn ->
          SessionContext.with_session([session_id: session_id], fn ->
            SnakeBridge.call("time", "sleep", [0.4], __runtime__: [pool_name: pool_name])
          end)
        end)
      end

    if contend?, do: Process.sleep(40)

    {result, duration_ms} =
      timed(fn ->
        callback = fn item -> send(self(), {:stream_item, item}) end

        SnakeBridge.Runtime.Streamer.stream_dynamic(
          "itertools",
          "repeat",
          [ref, 2],
          [__runtime__: [pool_name: pool_name, affinity: affinity, session_id: session_id]],
          callback
        )
      end)

    items = collect_stream_items([])
    current_worker = wait_for_worker_id(session_id, 10)
    IO.puts("  Call duration: #{duration_ms}ms")
    IO.puts("  Current worker: #{current_worker || "unknown"}")

    case {label, result} do
      {"strict_queue", {:ok, :done}} ->
        IO.puts("  Stream completed (items=#{length(items)})")

      {"strict_queue", {:error, :worker_busy}} ->
        IO.puts("  Strict queue stream returned :worker_busy under contention")

      {"strict_queue", {:error, reason}} ->
        IO.puts("  Strict queue stream failed: #{inspect(reason)}")
        Examples.record_failure()

      {"hint", {:error, _reason}} ->
        IO.puts("  Hint mode fell back; stream ref failed as expected")

      {"hint", {:ok, :done}} ->
        IO.puts("  Hint mode stream succeeded (no fallback observed)")

      _ ->
        IO.puts("  Unexpected stream result: #{inspect(result)}")
        Examples.record_failure()
    end

    if sleep_task do
      _ = Task.await(sleep_task, 5_000)
    end

    IO.puts("")
  end

  defp collect_stream_items(acc) do
    receive do
      {:stream_item, item} ->
        collect_stream_items([item | acc])
    after
      0 ->
        Enum.reverse(acc)
    end
  end

  # ============================================================================
  # Demo 7: Named Sessions for Reuse
  # ============================================================================

  defp demo_named_sessions do
    IO.puts("Using named sessions that can be reused across calls...")
    IO.puts("")

    # First call - creates Path in named session
    name1 =
      SessionContext.with_session([session_id: "analytics_session"], fn ->
        {:ok, ref} = Runtime.call_dynamic("pathlib", "Path", ["/data/analytics/report1.csv"])
        {:ok, name} = Dynamic.get_attr(ref, :name)
        IO.puts("  First call in 'analytics_session':")
        IO.puts("    Path('/data/analytics/report1.csv').name = #{inspect(name)}")
        name
      end)

    # Second call - same session name, new objects but same isolation boundary
    name2 =
      SessionContext.with_session([session_id: "analytics_session"], fn ->
        {:ok, ref} = Runtime.call_dynamic("pathlib", "Path", ["/data/analytics/report2.csv"])
        {:ok, name} = Dynamic.get_attr(ref, :name)
        IO.puts("  Second call in 'analytics_session':")
        IO.puts("    Path('/data/analytics/report2.csv').name = #{inspect(name)}")
        name
      end)

    # Different session, independent state
    name3 =
      SessionContext.with_session([session_id: "other_session"], fn ->
        {:ok, ref} = Runtime.call_dynamic("pathlib", "Path", ["/data/other/data.json"])
        {:ok, name} = Dynamic.get_attr(ref, :name)
        IO.puts("  Call in 'other_session':")
        IO.puts("    Path('/data/other/data.json').name = #{inspect(name)}")
        name
      end)

    if name1 && name2 && name3 do
      IO.puts("")
      IO.puts("  Named sessions work correctly")
    else
      Examples.record_failure()
    end
  end

  # ============================================================================
  # Demo 8: Parallel Processing Pattern
  # ============================================================================

  defp demo_parallel_processing do
    IO.puts("Processing items in parallel, each with isolated session...")
    IO.puts("")

    items = [
      %{id: 1, data: [1, 2, 3, 4, 5]},
      %{id: 2, data: [10, 20, 30]},
      %{id: 3, data: [100, 200]},
      %{id: 4, data: [7, 8, 9, 10, 11, 12]}
    ]

    results =
      items
      |> Task.async_stream(
        fn item ->
          SessionContext.with_session([session_id: "worker_#{item.id}"], fn ->
            # Each worker has isolated Python state
            {:ok, sum} = SnakeBridge.call("builtins", "sum", [item.data])
            {:ok, length} = SnakeBridge.call("builtins", "len", [item.data])
            session = SnakeBridge.current_session()

            %{
              id: item.id,
              session: session,
              sum: sum,
              count: length,
              avg: sum / length
            }
          end)
        end,
        max_concurrency: 4
      )
      |> Enum.map(fn {:ok, result} -> result end)
      |> Enum.sort_by(& &1.id)

    IO.puts("  Results from parallel workers:")
    IO.puts("")

    Enum.each(results, fn r ->
      IO.puts(
        "    Worker #{r.id} (#{r.session}): sum=#{r.sum}, count=#{r.count}, avg=#{Float.round(r.avg, 2)}"
      )
    end)

    # Verify all sessions were different
    sessions = Enum.map(results, & &1.session) |> Enum.uniq()

    IO.puts("")

    if length(sessions) == length(results) do
      IO.puts("  All #{length(sessions)} workers had isolated sessions")
    else
      IO.puts("  ERROR: Expected #{length(results)} unique sessions, got #{length(sessions)}")
      Examples.record_failure()
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

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
