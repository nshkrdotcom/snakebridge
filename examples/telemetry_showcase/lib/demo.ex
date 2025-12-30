defmodule Demo do
  @moduledoc """
  SnakeBridge Telemetry Showcase Demo

  Demonstrates telemetry integration by showing:
  1. Call start/stop events with timing
  2. Error events when calls fail
  3. Multiple concurrent calls showing event interleaving
  4. Aggregate metrics at the end

  Run with: mix run -e Demo.run
  """

  alias TelemetryShowcase.TelemetryHandler
  alias SnakeBridge.Examples

  def run do
    # Start the telemetry handler agent
    {:ok, _pid} = TelemetryHandler.start_link()

    Snakepit.run_as_script(fn ->
      Examples.reset_failures()

      # Attach telemetry handlers AFTER Snakepit startup.
      TelemetryHandler.attach()
      SnakeBridge.Telemetry.RuntimeForwarder.attach()

      try do
        print_header()

        # Section 1: Basic calls with telemetry
        demo_basic_calls_with_telemetry()

        # Section 2: Error handling with telemetry
        demo_error_telemetry()

        # Section 3: Concurrent calls showing interleaving
        demo_concurrent_calls()

        # Section 4: Aggregate metrics
        TelemetryHandler.print_summary()

        print_footer()
        Examples.assert_no_failures!()
      after
        TelemetryHandler.detach()
        SnakeBridge.Telemetry.RuntimeForwarder.detach()
      end
    end)
    |> Examples.assert_script_ok()
  end

  # ============================================================
  # SECTION 1: BASIC CALLS WITH TELEMETRY
  # ============================================================

  defp demo_basic_calls_with_telemetry do
    IO.puts("""

    ================================================================================
                    SECTION 1: Basic Calls with Telemetry Events
    ================================================================================

    Each Python call emits telemetry events that we capture and display inline.
    Watch for the [:snakepit, :python, :call, :start] and :stop events!

    """)

    # Call 1: Square root
    python_call_with_telemetry(
      description: "Calculate square root of 144",
      elixir_call: "Math.sqrt/1",
      python_module: "math",
      python_function: "sqrt",
      args: [144]
    )

    # Call 2: Sine function
    python_call_with_telemetry(
      description: "Calculate sin(1.0)",
      elixir_call: "Math.sin/1",
      python_module: "math",
      python_function: "sin",
      args: [1.0]
    )

    # Call 3: Power function
    python_call_with_telemetry(
      description: "Calculate 2^10",
      elixir_call: "Math.pow/2",
      python_module: "math",
      python_function: "pow",
      args: [2, 10]
    )

    # Call 4: Calculate floor
    python_call_with_telemetry(
      description: "Calculate floor of 3.7",
      elixir_call: "Math.floor/1",
      python_module: "math",
      python_function: "floor",
      args: [3.7]
    )
  end

  # ============================================================
  # SECTION 2: ERROR HANDLING WITH TELEMETRY
  # ============================================================

  defp demo_error_telemetry do
    IO.puts("""

    ================================================================================
                    SECTION 2: Error Events in Telemetry
    ================================================================================

    When Python calls fail, telemetry captures the exception event.
    This allows monitoring systems to track error rates and patterns.

    """)

    # Call that will fail: sqrt of negative number
    python_call_with_telemetry(
      description: "Calculate sqrt(-1) - expected to fail!",
      elixir_call: "Math.sqrt/1",
      python_module: "math",
      python_function: "sqrt",
      args: [-1],
      expect_error: true
    )

    # Call with invalid module
    python_call_with_telemetry(
      description: "Call non-existent module - expected to fail!",
      elixir_call: "NonExistent.foo/0",
      python_module: "this_module_does_not_exist",
      python_function: "foo",
      args: [],
      expect_error: true
    )
  end

  # ============================================================
  # SECTION 3: CONCURRENT CALLS
  # ============================================================

  defp demo_concurrent_calls do
    IO.puts("""

    ================================================================================
                    SECTION 3: Concurrent Calls with Interleaved Events
    ================================================================================

    When multiple calls happen concurrently, telemetry events may interleave.
    This demonstrates how telemetry captures the true execution order.

    Starting 5 concurrent Python calls...

    """)

    # Launch concurrent tasks
    tasks =
      [
        {"sqrt(100)", "math", "sqrt", [100]},
        {"sin(0)", "math", "sin", [0]},
        {"cos(0)", "math", "cos", [0]},
        {"floor(3.7)", "math", "floor", [3.7]},
        {"ceil(2.3)", "math", "ceil", [2.3]}
      ]
      |> Enum.map(fn {desc, mod, func, args} ->
        Task.async(fn ->
          start = System.monotonic_time(:microsecond)
          result = snakepit_call(mod, func, args)
          elapsed = System.monotonic_time(:microsecond) - start

          IO.puts("│  [Concurrent] #{desc} = #{format_result(result)} (#{elapsed} us)")
          result
        end)
      end)

    IO.puts("│")
    IO.puts("│  Waiting for all concurrent calls to complete...")
    IO.puts("│")

    # Wait for all tasks
    results = Task.await_many(tasks, 30_000)
    Enum.each(results, &record_expectation(false, &1))

    IO.puts("│")
    IO.puts("│  All #{length(results)} concurrent calls completed!")
    IO.puts("│")
    IO.puts("└─ Concurrent execution finished")
    IO.puts("")
  end

  # ============================================================
  # VERBOSE PYTHON CALL HELPER
  # ============================================================

  defp python_call_with_telemetry(opts) do
    description = Keyword.fetch!(opts, :description)
    elixir_call = Keyword.fetch!(opts, :elixir_call)
    python_module = Keyword.fetch!(opts, :python_module)
    python_function = Keyword.fetch!(opts, :python_function)
    args = Keyword.fetch!(opts, :args)
    expect_error = Keyword.get(opts, :expect_error, false)

    IO.puts("┌─ #{description}")
    IO.puts("│")
    IO.puts("│  Elixir call:     #{elixir_call}")
    IO.puts("│  Python module:   #{python_module}")
    IO.puts("│  Arguments:       #{format_args(args)}")

    # Make the actual Python call
    # Telemetry events will be printed by the handler during this call
    start_time = System.monotonic_time(:microsecond)
    result = snakepit_call(python_module, python_function, args)
    elapsed = System.monotonic_time(:microsecond) - start_time

    IO.puts("│")

    record_expectation(expect_error, result)

    case result do
      {:ok, value} ->
        IO.puts("│  Response from Python (#{elapsed} us)")
        IO.puts("│")
        IO.puts("└─ Result: {:ok, #{inspect(value, limit: 50, printable_limit: 100)}}")

      {:error, reason} ->
        IO.puts("│  Error from Python (#{elapsed} us)")
        IO.puts("│")
        IO.puts("└─ Result: {:error, #{inspect(reason, limit: 50)}}")

      other ->
        IO.puts("│  Response (#{elapsed} us)")
        IO.puts("│")
        IO.puts("└─ Result: #{inspect(other, limit: 50)}")
    end

    IO.puts("")
    result
  end

  # ============================================================
  # FORMATTING HELPERS
  # ============================================================

  defp format_args([]), do: "(none)"
  defp format_args(args), do: inspect(args, limit: 50, printable_limit: 100)

  defp format_result({:ok, value}), do: inspect(value, limit: 20)
  defp format_result({:error, _}), do: "<error>"
  defp format_result(other), do: inspect(other, limit: 20)

  defp record_expectation(true, {:ok, _value}), do: Examples.record_failure()
  defp record_expectation(true, {:error, _reason}), do: :ok
  defp record_expectation(true, _other), do: Examples.record_failure()

  defp record_expectation(false, {:ok, _value}), do: :ok
  defp record_expectation(false, _other), do: Examples.record_failure()

  # ============================================================
  # HEADER/FOOTER
  # ============================================================

  defp print_header do
    IO.puts("""
    ================================================================================
                     SNAKEBRIDGE TELEMETRY SHOWCASE DEMO
    ================================================================================

    This demo shows how SnakeBridge integrates with Erlang's :telemetry library.
    You'll see telemetry events printed inline with each Python call.

    Events captured:
      - [:snakepit, :python, :call, :start]   - When a Python call begins
      - [:snakepit, :python, :call, :stop]    - When a Python call completes
      - [:snakepit, :python, :call, :exception] - When a Python call fails

    SnakeBridge also enriches these events via RuntimeForwarder:
      - [:snakebridge, :runtime, :call, :start]
      - [:snakebridge, :runtime, :call, :stop]
      - [:snakebridge, :runtime, :call, :exception]

    ================================================================================
    """)
  end

  defp print_footer do
    IO.puts("""

    ================================================================================
                              DEMO COMPLETE
    ================================================================================

    What you learned:
      1. Telemetry events are emitted automatically for every Python call
      2. Events include timing measurements (duration in native units)
      3. Error events capture exception details for monitoring
      4. Concurrent calls produce interleaved events
      5. Aggregate metrics help track overall system health

    To integrate telemetry in your own app:
      1. Use :telemetry.attach/4 to subscribe to events
      2. Forward metrics to your observability stack (Prometheus, Datadog, etc.)
      3. Use telemetry_metrics for aggregation

    ================================================================================
    """)
  end

  # Helper to call Python via Snakepit with proper payload format
  defp snakepit_call(python_module, python_function, args) do
    start_time = System.monotonic_time()

    payload =
      SnakeBridge.Runtime.protocol_payload()
      |> Map.merge(%{
        "library" => python_module |> String.split(".") |> List.first(),
        "python_module" => python_module,
        "function" => python_function,
        "args" => args,
        "kwargs" => %{},
        "idempotent" => false
      })

    metadata = %{
      module: python_module,
      function: python_function,
      library: payload["library"]
    }

    emit_call_event(
      [:snakepit, :python, :call, :start],
      %{system_time: System.system_time()},
      metadata
    )

    result = Snakepit.execute("snakebridge.call", payload)

    case result do
      {:ok, value} ->
        emit_call_event(
          [:snakepit, :python, :call, :stop],
          %{duration: System.monotonic_time() - start_time},
          metadata
        )

        {:ok, value}

      {:error, reason} ->
        emit_call_event(
          [:snakepit, :python, :call, :exception],
          %{duration: System.monotonic_time() - start_time},
          Map.put(metadata, :error, reason)
        )

        {:error, reason}

      other ->
        emit_call_event(
          [:snakepit, :python, :call, :stop],
          %{duration: System.monotonic_time() - start_time},
          metadata
        )

        {:ok, other}
    end
  end

  defp emit_call_event(event, measurements, metadata) do
    case Application.ensure_all_started(:telemetry) do
      {:ok, _} -> :telemetry.execute(event, measurements, metadata)
      {:error, _} -> :ok
    end
  end
end
