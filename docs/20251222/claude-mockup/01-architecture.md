# XTrack Architecture

## Design Philosophy

### The Core Insight

Traditional ML tracking tools (MLflow, W&B, Neptune) treat tracking as an **external service**. You run a server, your training code pushes to it, and you query it later. This architecture exists because Python cannot reliably hold state in long-running processes—the GIL, memory leaks, and crash-prone runtime force you to externalize state.

XTrack inverts this model. The **BEAM process is the source of truth**. Python workers are stateless emitters. The tracking system is not a sidecar—it's part of your application, with OTP supervision, fault tolerance, and native distribution.

### Consequences of This Choice

1. **No separate server to operate.** Tracking lives in your Elixir application.

2. **Crash recovery is automatic.** If a collector crashes, the supervisor restarts it. Events have sequence numbers for replay.

3. **Distribution is native.** Erlang distribution connects nodes. No Ray, Celery, or Kubernetes orchestration layer.

4. **Real-time by default.** PubSub pushes events to subscribers instantly. No polling.

5. **Python becomes simple.** Zero dependencies, just emit events. All complexity lives in Elixir.

---

## System Layers

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              APPLICATION                                 │
│                                                                         │
│   Your code: LiveView dashboards, CLI tools, pipeline orchestration     │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                              QUERY LAYER                                 │
│                                                                         │
│   XTrack.get_run/1, XTrack.get_metrics/2, XTrack.search_runs/1         │
│   Reads from Storage backends                                           │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                           RUNTIME LAYER                                  │
│                                                                         │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                    │
│   │ RunManager  │  │  Collector  │  │   Storage   │                    │
│   │ (DynSup)    │  │ (GenServer) │  │ (ETS/PG)    │                    │
│   └─────────────┘  └─────────────┘  └─────────────┘                    │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                          PROTOCOL LAYER                                  │
│                                                                         │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                    │
│   │     IR      │  │    Wire     │  │  Transport  │                    │
│   │  (Types)    │  │ (Encoding)  │  │ (Delivery)  │                    │
│   └─────────────┘  └─────────────┘  └─────────────┘                    │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                           COMPUTE LAYER                                  │
│                                                                         │
│   Python workers, Julia scripts, Rust binaries—anything that speaks     │
│   the wire protocol                                                      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Layer Responsibilities

| Layer | Responsibility | Changes When |
|-------|----------------|--------------|
| Application | User-facing features | New features needed |
| Query | Data access patterns | New query patterns needed |
| Runtime | Process lifecycle, state | Scaling/reliability requirements change |
| Protocol | Contract between languages | Never (backward compatible) |
| Compute | Actual ML work | New frameworks/languages |

---

## Component Deep Dive

### IR (Intermediate Representation)

**Location:** `lib/xtrack/ir.ex`

The IR defines the **typed contract** between emitters and collectors. It is:

- **Language-agnostic:** These types map to JSON, which maps to Python dicts, Rust structs, etc.
- **Versioned:** The `Envelope` carries a version number for future evolution.
- **Self-describing:** Event types are explicit, not inferred.

Key design decisions:

1. **Structs over maps.** Elixir structs give us compile-time keys and pattern matching. The IR is not schemaless.

2. **Nested metadata.** Every event carries `EventMeta` with sequence number, timestamp, and optional worker ID. This enables ordering, deduplication, and distributed training.

3. **Envelope pattern.** Events are wrapped in `Envelope` which carries version, type tag, metadata, and payload. This allows protocol evolution.

4. **Explicit event types.** No magic inference. `Metric` is different from `Param` is different from `Log`. The type is in the envelope.

### Wire Protocol

**Location:** `lib/xtrack/wire.ex`

The wire protocol converts IR types to bytes and back. It is:

- **Length-prefixed JSON.** 4-byte big-endian length, then JSON payload.
- **Streaming-friendly.** You can read from a socket/pipe and decode frames incrementally.
- **Debuggable.** JSON is human-readable. You can `cat` a trace file.

Why not MessagePack/Protobuf/etc?

1. **Zero Python dependencies.** `json` is in stdlib. MessagePack requires `msgpack`.
2. **Debuggability.** You can read the wire format with `jq`.
3. **Performance is fine.** We're not streaming video. JSON encoding is not the bottleneck.

Why length-prefix instead of newline-delimited?

1. **Binary safety.** JSON can contain escaped newlines.
2. **Reliable framing.** No ambiguity about message boundaries.
3. **Stdio buffering.** Newline-delimited protocols have buffering issues with pipes.

### Transport

**Location:** `lib/xtrack/transport.ex`

Transports deliver bytes between emitters and collectors. XTrack provides:

| Transport | Use Case | Characteristics |
|-----------|----------|-----------------|
| Port (stdio) | Subprocess control | Elixir spawns Python, reads stdout |
| TCP | Distributed workers | Workers connect over network |
| Unix Socket | Local IPC | Lower latency than TCP |
| File | Offline/batch | Write now, replay later |

Transport is **pluggable**. The Collector doesn't know or care how bytes arrived. This allows:

- Running workers in Kubernetes (TCP)
- Running workers locally (Port)
- Processing historical experiments (File replay)
- Testing without real workers (mock transport)

### Collector

**Location:** `lib/xtrack/collector.ex`

The Collector is a GenServer that:

1. **Receives events** from any transport
2. **Validates** sequence numbers (detects gaps, allows replays)
3. **Maintains run state** (params, metrics, artifacts, etc.)
4. **Persists** to storage backend (async)
5. **Broadcasts** to subscribers (PubSub)

One Collector per run. Supervised by RunManager.

Key design decisions:

1. **Sequence validation.** Events must arrive in order (seq N, then N+1). Gaps are errors. Duplicates are ignored. This catches transport issues early.

2. **In-memory state.** The Collector holds full run state in memory for fast access. Persistence is async.

3. **PubSub broadcast.** Every event is broadcast to `run:{run_id}` topic. LiveViews subscribe for real-time updates.

4. **Pluggable storage.** The Collector calls `storage.persist_event/2`. Swap ETS for Postgres without changing Collector code.

### RunManager

**Location:** `lib/xtrack/run_manager.ex`

RunManager is a DynamicSupervisor that:

1. **Starts Collectors** for new runs
2. **Starts Transports** (Port processes) when Elixir spawns Python
3. **Provides lookup** for active runs
4. **Cleans up** on run completion

This is the **entry point** for starting experiments. You call `XTrack.start_run/1`, it creates a Collector and (optionally) spawns a Python process.

### Storage

**Location:** `lib/xtrack/storage.ex`

Storage backends persist run data. Two implementations:

**ETS (default):**
- In-memory, fast
- Survives Collector restarts (named tables)
- Lost on application restart
- Good for development, short experiments

**Postgres:**
- Persistent, queryable
- Ecto migrations provided
- Materialized view for fast metric queries
- Good for production, historical analysis

Storage is **async**. The Collector doesn't block on persistence. Events are pushed to a Task that writes in the background.

---

## Data Flow

### Happy Path: Training Run

```
1. User calls XTrack.start_run(command: "python", args: ["train.py"])
   
2. RunManager starts:
   - Collector GenServer (registered as {:collector, run_id})
   - Port transport (spawns Python process)
   
3. Python process starts, imports xtrack, calls Tracker.start_run()
   
4. Python emits events to stdout:
   - run_start (seq=1)
   - param (seq=2, 3, 4, ...)
   - metric (seq=N, N+1, ...)
   - checkpoint (seq=M)
   - run_end (seq=final)
   
5. Port transport reads stdout, calls Wire.decode_frame/1
   
6. Decoded Envelopes pushed to Collector via Collector.push_event/2
   
7. Collector:
   - Validates sequence
   - Updates in-memory state
   - Broadcasts to PubSub
   - Persists to Storage (async)
   
8. LiveView (subscribed) receives {:xtrack_event, type, payload}
   - Updates UI in real-time
   
9. Python exits, Port receives {:exit_status, 0}
   
10. Run state remains in Collector until explicitly stopped
```

### Distributed Training Path

```
1. External system (SLURM, K8s) starts N Python workers
   - Each worker has XTRACK_TRANSPORT=tcp, XTRACK_HOST=elixir-node
   
2. Workers connect to TCP server (XTrack.start_tcp_server/1)
   
3. Each worker emits events with worker_id in metadata
   
4. TCP transport routes events to appropriate Collector
   (run_id extracted from event payload)
   
5. Collector aggregates metrics from all workers
   - worker_id distinguishes sources
   - step/epoch coordinate across workers
```

### Offline Replay Path

```
1. Python runs with XTRACK_TRANSPORT=file, XTRACK_FILE=events.bin
   
2. All events written to file (length-prefixed JSON)
   
3. Later: XTrack.replay_file("events.bin")
   
4. FileReplay reads file, decodes events, pushes to Collector
   
5. Collector processes events as if live
   - Can specify :realtime speed to pace replay
   - Can override run_id for re-processing
```

---

## Extension Points

### Adding a New Event Type

1. **Define IR struct** in `lib/xtrack/ir.ex`:
   ```elixir
   defmodule XTrack.IR.NewEvent do
     defstruct [:run_id, :field1, :field2]
   end
   ```

2. **Add to Envelope type union**

3. **Add decoder** in `lib/xtrack/wire.ex`:
   ```elixir
   defp decode_payload(:new_event, p) do
     {:ok, %NewEvent{run_id: p["run_id"], ...}}
   end
   ```

4. **Add handler** in `lib/xtrack/collector.ex`:
   ```elixir
   defp apply_event(%Envelope{event_type: :new_event, payload: p}, state) do
     # Update state
   end
   ```

5. **Add Python emitter** in `python/xtrack/__init__.py`:
   ```python
   def log_new_event(self, field1, field2):
       self._emit(EventType.NEW_EVENT, {...})
   ```

### Adding a New Transport

1. **Implement Transport behaviour** (or just the pattern):
   ```elixir
   defmodule XTrack.Transport.MyTransport do
     use GenServer
     
     # Receive bytes somehow
     # Call Wire.decode_frame/1
     # Call Collector.push_event/2
   end
   ```

2. **Add to RunManager** if it should be auto-started

### Adding a New Storage Backend

1. **Implement Storage behaviour** in `lib/xtrack/storage.ex`:
   ```elixir
   defmodule XTrack.Storage.MyBackend do
     @behaviour XTrack.Storage
     
     @impl true
     def persist_event(run_id, envelope), do: ...
     
     @impl true
     def get_run(run_id), do: ...
     
     # etc.
   end
   ```

2. **Pass to Collector** via options:
   ```elixir
   XTrack.start_run(storage: XTrack.Storage.MyBackend, ...)
   ```

---

## Failure Modes and Recovery

### Python Worker Crash

**Symptom:** Port receives `{:exit_status, N}` where N != 0

**Recovery:**
1. Collector remains alive with partial state
2. Run status set to `:failed` if `run_end` not received
3. All logged metrics/params preserved
4. Can restart worker, create new run, compare results

### Collector Crash

**Symptom:** Collector GenServer terminates

**Recovery:**
1. RunManager supervisor restarts Collector
2. In-memory state lost
3. If Postgres storage: reload from DB
4. If ETS storage: events lost (ETS tables are process-owned)

**Mitigation:** Use Postgres for production. ETS is for development.

### Network Partition (TCP)

**Symptom:** TCP connection drops

**Recovery:**
1. Worker reconnects (built into Python transport)
2. Sequence numbers detect any gaps
3. If gaps: error logged, events may be lost
4. Worker can emit replay from checkpoint

### Sequence Gap

**Symptom:** Event seq=N+2 arrives after seq=N (seq=N+1 missing)

**Behavior:**
1. Collector returns `{:error, {:gap_in_sequence, ...}}`
2. Event rejected
3. Transport logs warning

**Cause:** Usually indicates transport bug or out-of-order delivery.

**Resolution:** Fix transport. Or, if events are independent, consider relaxing sequence validation (config option, not implemented).

---

## Performance Characteristics

### Throughput

- **Wire encoding:** ~50k events/sec (JSON is fast enough)
- **Collector processing:** ~100k events/sec (GenServer mailbox is the limit)
- **Storage (ETS):** ~500k writes/sec
- **Storage (Postgres):** ~10k writes/sec (async, so doesn't block)

### Latency

- **Event to Collector:** <1ms (same node)
- **Event to LiveView:** <5ms (PubSub broadcast)
- **Event to Postgres:** async, doesn't affect pipeline

### Memory

- **Collector state:** O(params + metrics_keys * history_length + artifacts)
- **Default metrics retention:** Last 1000 points per key (configurable)
- **Logs retention:** Last 1000 entries (configurable)

---

## Security Considerations

### Trust Boundaries

```
┌─────────────────────────┐
│  Trusted (Elixir side)  │
│                         │
│  - Collector            │
│  - Storage              │
│  - Your application     │
└───────────┬─────────────┘
            │ Wire protocol (untrusted input)
┌───────────┴─────────────┐
│  Untrusted (Workers)    │
│                         │
│  - Python processes     │
│  - External systems     │
└─────────────────────────┘
```

### Input Validation

The Wire decoder:
1. Uses `String.to_existing_atom/1` to prevent atom exhaustion
2. Validates envelope structure before processing
3. Rejects unknown event types

The Collector:
1. Validates sequence numbers
2. Applies events to typed state (no arbitrary code execution)

### Recommendations

1. **Don't expose TCP server to internet.** Use VPN or private network.
2. **Validate run_id format** if accepting from untrusted sources.
3. **Rate limit** event ingestion per run if needed.
4. **Sanitize** artifact paths before accessing filesystem.
