# XTrack Development Notes

This document contains implementation notes, design decisions, and guidance for future development.

---

## Design Decisions

### Why Length-Prefixed JSON?

**Alternatives Considered:**

1. **Newline-delimited JSON (NDJSON)**
   - Pro: Simple, grep-able
   - Con: JSON can contain escaped newlines
   - Con: Stdio buffering issues (Python buffers by line)
   - Con: No way to know message size upfront

2. **MessagePack**
   - Pro: Smaller, faster
   - Con: Requires Python dependency (`msgpack`)
   - Con: Not human-readable for debugging

3. **Protocol Buffers**
   - Pro: Schema enforcement, versioning
   - Con: Heavy dependency
   - Con: Code generation required

4. **Erlang External Term Format**
   - Pro: Native to BEAM
   - Con: Python implementation is sketchy
   - Con: Not human-readable

**Decision:** Length-prefixed JSON

- Zero Python dependencies (stdlib `json`)
- Human-readable for debugging (`jq`, etc.)
- Reliable framing over any byte stream
- Fast enough for experiment tracking

### Why One Collector Per Run?

**Alternatives Considered:**

1. **Single global collector**
   - Pro: Simpler architecture
   - Con: Single point of failure
   - Con: No isolation between runs
   - Con: Memory grows unbounded

2. **Collector pool**
   - Pro: Bounded resources
   - Con: Complex routing
   - Con: State locality issues

**Decision:** One GenServer per run

- Natural isolation
- Crash doesn't affect other runs
- State locality (all run data in one process)
- Simple supervision tree

### Why Sequence Numbers?

**Purpose:**
1. Detect transport issues (gaps = lost events)
2. Enable deduplication (replays are safe)
3. Allow ordering across workers

**Alternative: Timestamps Only**
- Con: Clock skew between workers
- Con: Can't detect lost events
- Con: Ordering ambiguous at same timestamp

**Decision:** Monotonic sequence + timestamp

- Sequence for ordering and gap detection
- Timestamp for human understanding
- Worker ID for distributed training

### Why PubSub Instead of Callbacks?

**Alternatives:**

1. **Callback functions**
   ```elixir
   XTrack.start_run(on_metric: fn m -> ... end)
   ```
   - Con: Callback runs in collector process
   - Con: Slow callback blocks event processing
   - Con: Crash in callback crashes collector

2. **Message passing to specific PID**
   ```elixir
   XTrack.subscribe(run_id, self())
   ```
   - Con: Must track subscribers manually
   - Con: Process death leaves stale refs

**Decision:** Phoenix.PubSub

- Decoupled from collector
- Handles subscriber lifecycle
- Supports multiple subscribers
- Works across nodes

---

## Implementation Notes

### Collector State Structure

```elixir
%{
  # Identity
  run_id: %RunId{},
  name: String.t(),
  
  # Lifecycle
  status: atom(),
  started_at: DateTime.t(),
  ended_at: DateTime.t() | nil,
  
  # Data
  params: %{String.t() => term()},      # Flat map, nested keys joined with "."
  metrics: %{String.t() => [point()]},  # Reverse chronological (newest first)
  artifacts: [Artifact.t()],            # Reverse chronological
  checkpoints: [Checkpoint.t()],        # Reverse chronological
  logs: [LogEntry.t()],                 # Reverse chronological, bounded
  
  # Tracking
  last_seq: non_neg_integer(),
  tags: %{String.t() => String.t()},
  
  # Metadata
  source: map() | nil,
  environment: map() | nil,
  
  # Internal
  storage: module(),
  max_logs: non_neg_integer(),
  subscribers: MapSet.t()  # (legacy, now using PubSub)
}
```

**Why reverse chronological?**
- New events prepended (O(1))
- Most recent is most accessed
- Truncation is easy (`Enum.take/2`)

### Wire Decoder State Machine

```
State: :waiting_for_length
  Input: 4+ bytes
  Action: Parse length, transition to :waiting_for_payload

State: :waiting_for_payload
  Input: `length` bytes
  Action: Decode JSON, emit envelope, transition to :waiting_for_length
  
State: :waiting_for_payload
  Input: < `length` bytes
  Action: Buffer, stay in state
```

```elixir
def decode_frame(<<len::big-unsigned-32, rest::binary>>) when byte_size(rest) >= len do
  <<json::binary-size(len), remaining::binary>> = rest
  {:ok, decode_json(json), remaining}
end

def decode_frame(<<len::big-unsigned-32, rest::binary>>) do
  {:incomplete, len - byte_size(rest)}
end

def decode_frame(data) when byte_size(data) < 4 do
  {:incomplete, 4 - byte_size(data)}
end
```

### Transport Buffer Management

Each transport maintains a buffer for incomplete frames:

```elixir
def handle_info({:tcp, socket, data}, state) do
  buffer = state.buffer <> data
  
  {events, remaining} = decode_all(buffer, [])
  
  # Process events
  Enum.each(events, &Collector.push_event(state.run_id, &1))
  
  {:noreply, %{state | buffer: remaining}}
end

defp decode_all(buffer, acc) do
  case Wire.decode_frame(buffer) do
    {:ok, envelope, rest} -> decode_all(rest, [envelope | acc])
    {:incomplete, _} -> {Enum.reverse(acc), buffer}
  end
end
```

### Storage Async Pattern

Storage writes are async to avoid blocking the collector:

```elixir
defp maybe_persist(state, envelope) do
  Task.start(fn ->
    state.storage.persist_event(state.run_id.id, envelope)
  end)
end
```

**Trade-off:**
- Pro: Collector never blocks on storage
- Con: Events may be lost if storage fails
- Mitigation: Log storage errors, retry queue (not implemented)

---

## Known Limitations

### No Backpressure

If Python emits faster than Elixir can process:
- Port mailbox grows unbounded
- TCP socket buffer fills
- Eventually OOM or dropped connections

**Mitigation:**
- Rate limit in Python (log every N steps)
- Increase Elixir processing capacity
- Use file transport for high-volume, process later

### No Event Replay from Storage

If collector crashes, in-memory state is lost. With Postgres storage, we could reload:

```elixir
# Not implemented
def recover_from_storage(run_id) do
  events = Storage.Postgres.get_events(run_id)
  
  state = Enum.reduce(events, initial_state(), fn envelope, state ->
    {:ok, state} = apply_event(envelope, state)
    state
  end)
  
  state
end
```

### Single Node Only

Current implementation doesn't handle:
- Collector on different node than transport
- Distributed storage coordination
- Cross-node PubSub (requires Phoenix.PubSub adapter)

**For multi-node:**
- Use `Phoenix.PubSub.PG2` adapter
- Store run→node mapping in distributed registry
- Route events to correct node

### No Schema Migration

Protocol version in envelope is unused. Future changes need:
- Version negotiation
- Payload transformers
- Backward compatibility layer

---

## Testing Strategies

### Unit Tests

```elixir
# Test IR types
test "Metric struct" do
  m = %Metric{run_id: "abc", key: "loss", value: 0.5, step: 100}
  assert m.key == "loss"
end

# Test Wire encoding/decoding
test "round-trip" do
  envelope = %Envelope{
    version: 1,
    event_type: :metric,
    meta: %EventMeta{seq: 1, timestamp_us: 123},
    payload: %Metric{run_id: "abc", key: "loss", value: 0.5}
  }
  
  {:ok, bytes} = Wire.encode_frame(envelope)
  {:ok, decoded, ""} = Wire.decode_frame(bytes)
  
  assert decoded == envelope
end
```

### Integration Tests

```elixir
test "full run lifecycle" do
  # Start collector
  {:ok, _} = XTrack.start_collector("test-run")
  XTrack.subscribe("test-run")
  
  # Simulate Python events
  events = [
    build_envelope(:run_start, 1, %{run_id: "test-run", name: "test"}),
    build_envelope(:param, 2, %{run_id: "test-run", key: "lr", value: 0.001}),
    build_envelope(:metric, 3, %{run_id: "test-run", key: "loss", value: 0.5, step: 0}),
    build_envelope(:run_end, 4, %{run_id: "test-run", status: "completed"})
  ]
  
  for e <- events do
    XTrack.Collector.push_event("test-run", e)
  end
  
  # Verify state
  {:ok, run} = XTrack.get_run("test-run")
  assert run.status == :completed
  assert run.params["lr"] == 0.001
  assert length(run.metrics["loss"]) == 1
end
```

### Python Integration Tests

```python
# test_xtrack.py
import subprocess
import json

def test_emit_events():
    # Run Python script that emits events
    proc = subprocess.Popen(
        ["python", "-c", """
from xtrack import Tracker
with Tracker.start_run(name="test") as run:
    run.log_param("lr", 0.001)
    run.log_metric("loss", 0.5, step=0)
"""],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    
    stdout, _ = proc.communicate()
    
    # Parse events from stdout
    events = parse_frames(stdout)
    
    assert len(events) == 4  # run_start, param, metric, run_end
    assert events[0]["t"] == "run_start"
    assert events[1]["t"] == "param"
    assert events[2]["t"] == "metric"
    assert events[3]["t"] == "run_end"
```

---

## Future Work

### Priority 1: Reliability

1. **Event replay from storage**
   - Reload collector state from Postgres on restart
   - Enable run resumption after crash

2. **Acknowledgment flow**
   - Optional ack for reliable delivery
   - Retry queue for failed persists

3. **Backpressure**
   - GenStage-based collector for flow control
   - Notify Python to slow down

### Priority 2: Features

1. **Artifact upload**
   - S3/GCS integration
   - Stream large files via separate channel
   - Content-addressable storage

2. **Comparison views**
   - Diff two runs
   - Parallel coordinates
   - Statistical significance tests

3. **Alerts**
   - Notify on metric threshold
   - Notify on run failure
   - Webhook integration

### Priority 3: Scale

1. **Multi-node support**
   - Distributed registry for run→node mapping
   - Cross-node event routing
   - Consistent hashing for collector placement

2. **Storage partitioning**
   - Time-based partitioning in Postgres
   - Archive old runs to cold storage
   - Separate hot/warm/cold tiers

3. **Query optimization**
   - Materialized views for common queries
   - Caching layer for active runs
   - Async aggregation workers

### Priority 4: Ecosystem

1. **CLI tool**
   - `xtrack list runs`
   - `xtrack show run-id`
   - `xtrack compare run-1 run-2`

2. **Jupyter integration**
   - Display runs in notebook
   - Interactive charts

3. **VSCode extension**
   - Show run status in sidebar
   - Jump to run from code

---

## Code Style

### Elixir

- Follow standard Elixir conventions
- Use `@moduledoc` and `@doc` for all public functions
- Types with `@type` and `@spec`
- Pattern match in function heads, not `case`

```elixir
# Good
def handle(%Envelope{event_type: :metric} = e), do: ...
def handle(%Envelope{event_type: :param} = e), do: ...

# Avoid
def handle(e) do
  case e.event_type do
    :metric -> ...
    :param -> ...
  end
end
```

### Python

- Type hints for all functions
- Docstrings for public API
- Zero external dependencies in core module
- Optional dependencies for framework integrations

```python
# Good
def log_metric(
    self,
    key: str,
    value: float,
    step: Optional[int] = None
) -> None:
    """Log a metric value.
    
    Args:
        key: Metric name
        value: Metric value
        step: Training step (optional)
    """
    ...
```

---

## Debugging

### Elixir

```elixir
# View collector state
{:ok, state} = XTrack.get_run("run-id")
IO.inspect(state, label: "run state")

# List all collectors
Registry.select(XTrack.Registry, [
  {{{:collector, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
])

# Trace events
:dbg.tracer()
:dbg.p(:all, :c)
:dbg.tpl(XTrack.Collector, :push_event, :x)
```

### Python

```python
# Enable debug logging
import logging
logging.basicConfig(level=logging.DEBUG)

# Inspect wire format
import struct
frame = transport._out.getvalue()
length = struct.unpack('>I', frame[:4])[0]
payload = frame[4:4+length]
print(json.loads(payload))
```

### Wire Protocol

```bash
# Decode events from file
python -c "
import struct, json, sys
data = open('events.bin', 'rb').read()
pos = 0
while pos < len(data):
    length = struct.unpack('>I', data[pos:pos+4])[0]
    payload = data[pos+4:pos+4+length]
    print(json.dumps(json.loads(payload), indent=2))
    pos += 4 + length
"

# Or use jq with custom decoder
```
