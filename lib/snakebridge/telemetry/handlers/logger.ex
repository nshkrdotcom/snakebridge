defmodule SnakeBridge.Telemetry.Handlers.Logger do
  @moduledoc """
  Logs SnakeBridge telemetry events.

  This handler logs compilation events at appropriate log levels:
  - Compile stop: `:info`
  - Compile exception: `:error`
  - Introspect/Generate: `:debug`

  ## Usage

      # In your application startup
      SnakeBridge.Telemetry.Handlers.Logger.attach()

  """

  require Logger

  @handler_id "snakebridge-logger"

  @events [
    [:snakebridge, :compile, :stop],
    [:snakebridge, :compile, :exception],
    [:snakebridge, :compile, :introspect, :stop],
    [:snakebridge, :compile, :generate, :stop]
  ]

  @doc """
  Attaches the logger handler to telemetry events.

  Returns `:ok` on success or `{:error, :already_exists}` if already attached.
  """
  @spec attach() :: :ok | {:error, :already_exists}
  def attach do
    :telemetry.attach_many(
      @handler_id,
      @events,
      &handle_event/4,
      %{}
    )
  end

  @doc """
  Detaches the logger handler.
  """
  @spec detach() :: :ok | {:error, :not_found}
  def detach do
    :telemetry.detach(@handler_id)
  end

  @doc false
  def handle_event([:snakebridge, :compile, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    libraries = metadata.details[:libraries] || []

    Logger.info(
      "SnakeBridge compiled #{measurements.symbols_generated} symbols " <>
        "in #{duration_ms}ms (#{length(libraries)} libraries)"
    )
  end

  def handle_event([:snakebridge, :compile, :exception], _measurements, metadata, _config) do
    reason = metadata.details[:reason]
    Logger.error("SnakeBridge compilation failed: #{inspect(reason)}")
  end

  def handle_event([:snakebridge, :compile, :introspect, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    python_time = metadata.details[:python_time] || 0
    python_ms = System.convert_time_unit(python_time, :native, :millisecond)

    Logger.debug(
      "Introspected #{measurements.symbols_introspected} symbols from #{metadata.library} " <>
        "in #{duration_ms}ms (Python: #{python_ms}ms, cache hits: #{measurements.cache_hits})"
    )
  end

  def handle_event([:snakebridge, :compile, :generate, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.debug(
      "Generated #{measurements.functions_generated} functions for #{metadata.library} " <>
        "in #{duration_ms}ms (#{measurements.bytes_written} bytes)"
    )
  end
end
