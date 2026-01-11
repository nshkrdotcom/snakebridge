# Session Affinity and Routing

SnakeBridge relies on Snakepit to route session-scoped calls to the same Python worker.
This matters whenever you keep state in Python memory (refs, model instances, caches,
open connections). Under load, the affinity mode determines whether routing is best-effort
or strict.

## Affinity Modes

- `:hint` (default) - best-effort routing. If the preferred worker is busy or unavailable,
  Snakepit may route the request to another worker. This can break ref-based calls.
- `:strict_queue` - strict routing. Requests queue until the preferred worker is available.
- `:strict_fail_fast` - strict routing with immediate error. Returns `{:error, :worker_busy}`
  when the preferred worker is busy.

When the preferred worker is missing or tainted, strict modes return
`{:error, :session_worker_unavailable}`.

## Configuration

Single pool (legacy config):

```elixir
# config/runtime.exs
SnakeBridge.ConfigHelper.configure_snakepit!(
  pool_size: 2,
  affinity: :strict_queue
)
```

Multi-pool with per-pool affinity:

```elixir
SnakeBridge.ConfigHelper.configure_snakepit!(
  pools: [
    %{name: :hint_pool, pool_size: 2, affinity: :hint},
    %{name: :strict_pool, pool_size: 2, affinity: :strict_queue}
  ]
)
```

Select a pool per call:

```elixir
SnakeBridge.call("math", "sqrt", [16], __runtime__: [pool_name: :strict_pool])
```

Refs retain the originating `pool_name` when provided, so subsequent ref
operations reuse the same pool even if you omit `pool_name`.

## Per-Call Overrides

You can override the pool default on any call:

```elixir
SnakeBridge.call("pathlib", "Path", ["."],
  __runtime__: [affinity: :strict_fail_fast]
)
```

Overrides also work in multi-pool mode:

```elixir
SnakeBridge.Dynamic.call(ref, :exists, [],
  __runtime__: [pool_name: :strict_pool, affinity: :hint]
)
```

## Streaming Calls

Streaming calls use the same affinity selection, but checkout does not queue.
If the preferred worker is busy, streaming calls return `{:error, :worker_busy}`
even under `:strict_queue`. Use `:strict_queue` to guarantee routing when the
worker is free, and `:strict_fail_fast` to make busy cases explicit.

## Auto-Sessions

If you do not pass a `session_id`, SnakeBridge creates a process-scoped auto-session.
Affinity applies once the session is established (after the first call assigns a
preferred worker).

Use strict affinity defaults when refs must never move across workers.

Session cleanup logs are opt-in via `config :snakebridge, session_cleanup_log_level: :debug`.
Cleanup also emits `[:snakebridge, :session, :cleanup]` telemetry events.

## Examples

- `examples/multi_session_example` - multi-pool hint vs strict modes, per-call overrides,
  tainted worker edge cases, and streaming with session-bound refs.
- `examples/affinity_defaults_example` - single-pool defaults and per-call overrides.

## Recommended Defaults

- Stateful refs or in-memory caches: `:strict_queue`
- Stateless or idempotent calls: `:hint`
- Latency-sensitive calls with explicit retry: `:strict_fail_fast`
