defmodule TelemetryShowcase.TelemetryHandler do
  @moduledoc """
  Custom telemetry handler that captures and prints SnakeBridge/Snakepit events
  inline with demo output for educational purposes.

  This handler demonstrates:
  - Capturing call start/stop events with timing
  - Capturing error/exception events
  - Tracking metrics for aggregate statistics
  """

  use Agent

  @handler_id "telemetry-showcase-handler"

  # Events we want to capture
  @events [
    # Snakepit runtime events (the actual Python calls)
    [:snakepit, :python, :call, :start],
    [:snakepit, :python, :call, :stop],
    [:snakepit, :python, :call, :exception],
    # SnakeBridge forwarded events
    [:snakebridge, :runtime, :call, :start],
    [:snakebridge, :runtime, :call, :stop],
    [:snakebridge, :runtime, :call, :exception]
  ]

  # ============================================================
  # PUBLIC API
  # ============================================================

  @doc """
  Starts the telemetry handler agent to track metrics.
  """
  def start_link(_opts \\ []) do
    Agent.start_link(
      fn ->
        %{
          events: [],
          call_count: 0,
          error_count: 0,
          total_duration_us: 0,
          durations: []
        }
      end,
      name: __MODULE__
    )
  end

  @doc """
  Attaches the telemetry handler to all relevant events.
  """
  def attach do
    :telemetry.attach_many(
      @handler_id,
      @events,
      &handle_event/4,
      %{print: true}
    )
  end

  @doc """
  Attaches the handler in silent mode (tracks metrics but doesn't print).
  """
  def attach_silent do
    :telemetry.attach_many(
      @handler_id,
      @events,
      &handle_event/4,
      %{print: false}
    )
  end

  @doc """
  Detaches the telemetry handler.
  """
  def detach do
    :telemetry.detach(@handler_id)
  end

  @doc """
  Resets all tracked metrics.
  """
  def reset_metrics do
    Agent.update(__MODULE__, fn _state ->
      %{
        events: [],
        call_count: 0,
        error_count: 0,
        total_duration_us: 0,
        durations: []
      }
    end)
  end

  @doc """
  Returns the current metrics.
  """
  def get_metrics do
    Agent.get(__MODULE__, & &1)
  end

  @doc """
  Prints a summary of collected metrics.
  """
  def print_summary do
    metrics = get_metrics()

    avg_duration =
      if metrics.call_count > 0 do
        Float.round(metrics.total_duration_us / metrics.call_count, 2)
      else
        0.0
      end

    error_rate =
      if metrics.call_count > 0 do
        Float.round(metrics.error_count / metrics.call_count * 100, 2)
      else
        0.0
      end

    {min_dur, max_dur} =
      case metrics.durations do
        [] -> {0, 0}
        durations -> {Enum.min(durations), Enum.max(durations)}
      end

    IO.puts("""

    ================================================================================
                              TELEMETRY METRICS SUMMARY
    ================================================================================

      Total calls:        #{metrics.call_count}
      Successful calls:   #{metrics.call_count - metrics.error_count}
      Failed calls:       #{metrics.error_count}
      Error rate:         #{error_rate}%

      Total duration:     #{metrics.total_duration_us} us
      Average duration:   #{avg_duration} us
      Min duration:       #{min_dur} us
      Max duration:       #{max_dur} us

      Events captured:    #{length(metrics.events)}

    ================================================================================
    """)
  end

  # ============================================================
  # TELEMETRY EVENT HANDLERS
  # ============================================================

  @doc false
  def handle_event([:snakepit, :python, :call, :start], measurements, metadata, config) do
    if config.print do
      print_start_event([:snakepit, :python, :call, :start], measurements, metadata)
    end
  end

  def handle_event([:snakepit, :python, :call, :stop], measurements, metadata, config) do
    duration_us = convert_duration(measurements)

    # Update metrics
    Agent.update(__MODULE__, fn state ->
      %{
        state
        | call_count: state.call_count + 1,
          total_duration_us: state.total_duration_us + duration_us,
          durations: [duration_us | state.durations],
          events: [{:stop, :erlang.monotonic_time(), measurements, metadata} | state.events]
      }
    end)

    if config.print do
      print_stop_event([:snakepit, :python, :call, :stop], measurements, metadata, duration_us)
    end
  end

  def handle_event([:snakepit, :python, :call, :exception], measurements, metadata, config) do
    duration_us = convert_duration(measurements)

    # Update metrics
    Agent.update(__MODULE__, fn state ->
      %{
        state
        | call_count: state.call_count + 1,
          error_count: state.error_count + 1,
          total_duration_us: state.total_duration_us + duration_us,
          durations: [duration_us | state.durations],
          events: [{:exception, :erlang.monotonic_time(), measurements, metadata} | state.events]
      }
    end)

    if config.print do
      print_exception_event(
        [:snakepit, :python, :call, :exception],
        measurements,
        metadata,
        duration_us
      )
    end
  end

  # SnakeBridge forwarded events (enriched with SnakeBridge context)
  def handle_event([:snakebridge, :runtime, :call, :start], measurements, metadata, config) do
    if config.print do
      print_start_event([:snakebridge, :runtime, :call, :start], measurements, metadata)
    end
  end

  def handle_event([:snakebridge, :runtime, :call, :stop], measurements, metadata, config) do
    duration_us = convert_duration(measurements)

    if config.print do
      print_stop_event(
        [:snakebridge, :runtime, :call, :stop],
        measurements,
        metadata,
        duration_us
      )
    end
  end

  def handle_event([:snakebridge, :runtime, :call, :exception], measurements, metadata, config) do
    duration_us = convert_duration(measurements)

    if config.print do
      print_exception_event(
        [:snakebridge, :runtime, :call, :exception],
        measurements,
        metadata,
        duration_us
      )
    end
  end

  # ============================================================
  # PRINTING HELPERS
  # ============================================================

  defp print_start_event(event, measurements, metadata) do
    IO.puts("│")
    IO.puts("│  -------------------------------------------------------")
    IO.puts("│  TELEMETRY EVENT: #{format_event(event)}")
    IO.puts("│     system_time: #{format_system_time(measurements)}")
    IO.puts("│     metadata: #{format_metadata(metadata)}")
    IO.puts("│  -------------------------------------------------------")
  end

  defp print_stop_event(event, measurements, metadata, duration_us) do
    IO.puts("│")
    IO.puts("│  -------------------------------------------------------")
    IO.puts("│  TELEMETRY EVENT: #{format_event(event)}")
    IO.puts("│     duration: #{duration_us} us")
    IO.puts("│     measurements: #{format_measurements(measurements)}")
    IO.puts("│     metadata: #{format_metadata(metadata)}")
    IO.puts("│  -------------------------------------------------------")
  end

  defp print_exception_event(event, measurements, metadata, duration_us) do
    IO.puts("│")
    IO.puts("│  -------------------------------------------------------")
    IO.puts("│  TELEMETRY EVENT: #{format_event(event)} [ERROR]")
    IO.puts("│     duration: #{duration_us} us")
    IO.puts("│     error: #{format_error(metadata)}")
    IO.puts("│     measurements: #{format_measurements(measurements)}")
    IO.puts("│  -------------------------------------------------------")
  end

  # ============================================================
  # FORMATTING HELPERS
  # ============================================================

  defp format_event(event) do
    event
    |> Enum.map(&Atom.to_string/1)
    |> Enum.map(&(":" <> &1))
    |> then(&("[" <> Enum.join(&1, ", ") <> "]"))
  end

  defp format_system_time(measurements) do
    case Map.get(measurements, :system_time) do
      nil -> "N/A"
      time -> "#{time}"
    end
  end

  defp format_measurements(measurements) do
    measurements
    |> Map.drop([:system_time])
    |> inspect(limit: 5, pretty: false)
  end

  defp format_metadata(metadata) do
    # Extract key fields for display
    fields =
      metadata
      |> Map.take([:module, :function, :library, :snakebridge_library, :snakebridge_version])
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    if map_size(fields) == 0 do
      inspect(metadata, limit: 3, pretty: false)
    else
      inspect(fields, limit: 5, pretty: false)
    end
  end

  defp format_error(metadata) do
    case Map.get(metadata, :reason) do
      nil -> inspect(Map.get(metadata, :error, "unknown"), limit: 50)
      reason -> inspect(reason, limit: 50)
    end
  end

  defp convert_duration(measurements) do
    case Map.get(measurements, :duration) do
      nil -> 0
      duration -> System.convert_time_unit(duration, :native, :microsecond)
    end
  end
end
