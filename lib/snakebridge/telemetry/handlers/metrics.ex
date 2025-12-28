defmodule SnakeBridge.Telemetry.Handlers.Metrics do
  @moduledoc """
  Metric definitions for SnakeBridge telemetry.

  This module provides metric definitions compatible with TelemetryMetrics
  and reporters like TelemetryMetricsPrometheus.

  ## Usage

      # In your application with TelemetryMetricsPrometheus
      TelemetryMetricsPrometheus.Core.attach(
        SnakeBridge.Telemetry.Handlers.Metrics.metrics()
      )

  ## Metrics

  ### Compilation
  - `snakebridge.compile.duration` - Distribution of compilation times
  - `snakebridge.compile.symbols_generated` - Sum of symbols generated
  - `snakebridge.compile.total` - Counter of compilations

  ### Scanning
  - `snakebridge.scan.duration` - Distribution of scan times
  - `snakebridge.scan.files_scanned` - Sum of files scanned
  - `snakebridge.scan.symbols_found` - Sum of symbols found

  ### Introspection
  - `snakebridge.introspect.duration` - Distribution of introspection times
  - `snakebridge.introspect.symbols_introspected` - Sum of symbols introspected
  - `snakebridge.introspect.cache_hits` - Sum of cache hits

  ### Generation
  - `snakebridge.generate.duration` - Distribution of generation times
  - `snakebridge.generate.bytes_written` - Sum of bytes written

  ### Documentation
  - `snakebridge.docs.fetch.duration` - Distribution of doc fetch times
  - `snakebridge.docs.fetch.total` - Counter of doc fetches

  """

  @doc """
  Returns a list of Telemetry.Metrics definitions.

  These can be used with any TelemetryMetrics-compatible reporter.
  """
  @spec metrics() :: [struct()]
  def metrics do
    import Telemetry.Metrics

    [
      # Compilation metrics
      distribution("snakebridge.compile.duration",
        event_name: [:snakebridge, :compile, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        reporter_options: [buckets: [100, 500, 1000, 5000, 10_000]]
      ),
      sum("snakebridge.compile.symbols_generated",
        event_name: [:snakebridge, :compile, :stop],
        measurement: :symbols_generated
      ),
      counter("snakebridge.compile.total",
        event_name: [:snakebridge, :compile, :stop]
      ),

      # Scan metrics
      distribution("snakebridge.scan.duration",
        event_name: [:snakebridge, :scan, :stop],
        measurement: :duration,
        unit: {:native, :millisecond}
      ),
      sum("snakebridge.scan.files_scanned",
        event_name: [:snakebridge, :scan, :stop],
        measurement: :files_scanned
      ),
      sum("snakebridge.scan.symbols_found",
        event_name: [:snakebridge, :scan, :stop],
        measurement: :symbols_found
      ),

      # Introspection metrics
      distribution("snakebridge.introspect.duration",
        event_name: [:snakebridge, :introspect, :stop],
        measurement: :duration,
        tags: [:library],
        unit: {:native, :millisecond}
      ),
      sum("snakebridge.introspect.symbols_introspected",
        event_name: [:snakebridge, :introspect, :stop],
        measurement: :symbols_introspected,
        tags: [:library]
      ),
      sum("snakebridge.introspect.cache_hits",
        event_name: [:snakebridge, :introspect, :stop],
        measurement: :cache_hits,
        tags: [:library]
      ),

      # Generation metrics
      distribution("snakebridge.generate.duration",
        event_name: [:snakebridge, :generate, :stop],
        measurement: :duration,
        tags: [:library],
        unit: {:native, :millisecond}
      ),
      sum("snakebridge.generate.bytes_written",
        event_name: [:snakebridge, :generate, :stop],
        measurement: :bytes_written,
        tags: [:library]
      ),

      # Documentation metrics
      distribution("snakebridge.docs.fetch.duration",
        event_name: [:snakebridge, :docs, :fetch],
        measurement: :duration,
        tags: [:source],
        unit: {:native, :millisecond}
      ),
      counter("snakebridge.docs.fetch.total",
        event_name: [:snakebridge, :docs, :fetch],
        tags: [:source]
      )
    ]
  end
end
