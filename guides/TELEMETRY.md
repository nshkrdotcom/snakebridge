# Telemetry and Observability

SnakeBridge emits `:telemetry` events for compilation, runtime calls, sessions, and
documentation fetches. These events enable logging, metrics collection, and custom
monitoring integrations.

## Event Categories

### Compile-time Events

Emitted during `mix compile` when generating wrapper modules:

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:snakebridge, :compile, :start]` | `system_time` | `library`, `phase`, `details` |
| `[:snakebridge, :compile, :stop]` | `duration`, `symbols_generated`, `files_written` | `library`, `phase`, `details` |
| `[:snakebridge, :compile, :exception]` | `duration` | `library`, `phase`, `details` |
| `[:snakebridge, :compile, :scan, :stop]` | `duration`, `files_scanned`, `symbols_found` | `library`, `phase`, `details` |
| `[:snakebridge, :compile, :introspect, :start]` | `system_time` | `library`, `phase`, `details` |
| `[:snakebridge, :compile, :introspect, :stop]` | `duration`, `symbols_introspected`, `cache_hits` | `library`, `phase`, `details` |
| `[:snakebridge, :compile, :generate, :stop]` | `duration`, `bytes_written`, `functions_generated`, `classes_generated` | `library`, `phase`, `details` |

### Runtime Events

Forwarded from Snakepit via RuntimeForwarder (see below):

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:snakebridge, :runtime, :call, :start]` | `system_time` | `library`, `function`, `call_type`, `snakebridge_version` |
| `[:snakebridge, :runtime, :call, :stop]` | `duration` | `library`, `function`, `call_type`, `snakebridge_version` |
| `[:snakebridge, :runtime, :call, :exception]` | `duration` | `library`, `function`, `call_type`, `snakebridge_version` |

### Session Events

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:snakebridge, :session, :cleanup]` | `system_time` | `session_id`, `source`, `reason` |

The `source` is `:manual` or `:owner_down`. The `reason` provides the exit reason.

### Documentation Events

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:snakebridge, :docs, :fetch]` | `duration` | `module`, `function`, `source` |
| `[:snakebridge, :lock, :verify]` | `duration` | `result`, `warnings` |

## Measurements and Metadata

All timed events include `duration` in native time units. Convert with:

```elixir
duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
```

Common metadata fields:
- `library` - Target library (`:all` for full compile, specific atom for phases)
- `phase` - One of `:compile`, `:scan`, `:introspect`, `:generate`
- `details` - Phase-specific map with additional context

## RuntimeForwarder

Bridges Snakepit's Python call events into the SnakeBridge namespace:

```elixir
# In your application startup
SnakeBridge.Telemetry.RuntimeForwarder.attach()
```

Listens to `[:snakepit, :python, :call, ...]` and re-emits as
`[:snakebridge, :runtime, :call, ...]` with added `snakebridge_version`.

## Built-in Handlers

### Logger Handler

```elixir
SnakeBridge.Telemetry.Handlers.Logger.attach()
```

Log levels:
- `:info` - Compile success
- `:error` - Compile exception
- `:debug` - Introspection and generation details

Example output:

```
[info] SnakeBridge compiled 42 symbols in 1234ms (3 libraries)
[debug] Introspected 15 symbols from numpy in 456ms (Python: 400ms, cache hits: 5)
```

### Metrics Handler (Prometheus)

```elixir
metrics = SnakeBridge.Telemetry.Handlers.Metrics.metrics()
TelemetryMetricsPrometheus.Core.attach(metrics)
```

## Custom Handler Example

```elixir
defmodule MyApp.SnakeBridgeHandler do
  @events [
    [:snakebridge, :compile, :stop],
    [:snakebridge, :runtime, :call, :stop]
  ]

  def attach do
    :telemetry.attach_many("my-handler", @events, &handle_event/4, %{})
  end

  def handle_event([:snakebridge, :compile, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    libraries = metadata.details[:libraries] || []

    MyApp.Metrics.record(:snakebridge_compile, %{
      duration_ms: duration_ms,
      symbols: measurements.symbols_generated,
      libraries: length(libraries)
    })
  end

  def handle_event([:snakebridge, :runtime, :call, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    MyApp.Metrics.histogram(:python_call_duration, duration_ms, %{
      library: metadata.library,
      function: metadata.function
    })
  end
end
```

## Configuration

Session cleanup events can be logged at a configurable level:

```elixir
# config/config.exs
config :snakebridge, session_cleanup_log_level: :debug
```

## Metrics Definition Reference

### Compilation Metrics

| Metric | Type | Tags |
|--------|------|------|
| `snakebridge.compile.duration` | Distribution | - |
| `snakebridge.compile.symbols_generated` | Sum | - |
| `snakebridge.compile.total` | Counter | - |

### Scan Metrics

| Metric | Type | Tags |
|--------|------|------|
| `snakebridge.scan.duration` | Distribution | - |
| `snakebridge.scan.files_scanned` | Sum | - |
| `snakebridge.scan.symbols_found` | Sum | - |

### Introspection Metrics

| Metric | Type | Tags |
|--------|------|------|
| `snakebridge.introspect.duration` | Distribution | `library` |
| `snakebridge.introspect.symbols_introspected` | Sum | `library` |
| `snakebridge.introspect.cache_hits` | Sum | `library` |

### Generation Metrics

| Metric | Type | Tags |
|--------|------|------|
| `snakebridge.generate.duration` | Distribution | `library` |
| `snakebridge.generate.bytes_written` | Sum | `library` |

### Documentation Metrics

| Metric | Type | Tags |
|--------|------|------|
| `snakebridge.docs.fetch.duration` | Distribution | `source` |
| `snakebridge.docs.fetch.total` | Counter | `source` |

Distribution metrics use default buckets: `[100, 500, 1000, 5000, 10_000]` ms.

## See Also

- `examples/telemetry_showcase/` - Full telemetry demonstration
- [Telemetry](https://hexdocs.pm/telemetry) - Core telemetry library
- [TelemetryMetricsPrometheus](https://hexdocs.pm/telemetry_metrics_prometheus) - Prometheus export
