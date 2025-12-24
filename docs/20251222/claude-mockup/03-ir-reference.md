# XTrack IR Type Reference

This document describes the Elixir types that make up the XTrack Intermediate Representation.

---

## Overview

The IR defines the **typed contract** between emitters and collectors. All types are defined in `lib/xtrack/ir.ex`.

```
XTrack.IR
├── RunId           # Run identity
├── EventMeta       # Event metadata
├── Envelope        # Wire wrapper
│
├── RunStart        # Run initialization
├── RunEnd          # Run completion
├── Param           # Hyperparameter
├── Metric          # Single metric
├── MetricBatch     # Multiple metrics
├── Artifact        # File artifact
├── Checkpoint      # Training checkpoint
├── StatusUpdate    # Status change
├── LogEntry        # Log message
│
├── Command         # Control command (bidirectional)
└── Ack             # Acknowledgment (bidirectional)
```

---

## Identity Types

### RunId

Identifies a run within the tracking system.

```elixir
defmodule XTrack.IR.RunId do
  @type t :: %__MODULE__{
    id: String.t(),                    # Unique run identifier (UUID)
    experiment_id: String.t() | nil,   # Parent experiment for grouping
    parent_run_id: String.t() | nil    # Parent run (for nested/child runs)
  }
  
  defstruct [:id, :experiment_id, :parent_run_id]
end
```

**Usage:**
```elixir
# Simple run
%RunId{id: "abc-123"}

# Run within an experiment
%RunId{id: "abc-123", experiment_id: "lr-sweep-001"}

# Child run (e.g., cross-validation fold)
%RunId{id: "fold-1", parent_run_id: "cv-run-main"}
```

**Design Notes:**
- `id` should be globally unique (UUID recommended)
- `experiment_id` enables grouping related runs
- `parent_run_id` enables hierarchical run structures

---

### EventMeta

Metadata attached to every event.

```elixir
defmodule XTrack.IR.EventMeta do
  @type t :: %__MODULE__{
    seq: non_neg_integer(),           # Monotonic sequence within run
    timestamp_us: integer(),           # Microseconds since epoch
    worker_id: String.t() | nil,       # Worker identifier
    received_at: DateTime.t() | nil    # Set by collector on receipt
  }
  
  defstruct [:seq, :timestamp_us, :worker_id, :received_at]
end
```

**Invariants:**
- `seq` starts at 1 and increments by 1
- `seq` is unique within a (run_id, worker_id) pair
- `timestamp_us` is worker's local clock
- `received_at` is set by collector, not emitter

**Usage in Collector:**
```elixir
# Validate sequence
cond do
  meta.seq <= state.last_seq -> {:ok, state}  # Duplicate, ignore
  meta.seq > state.last_seq + 1 -> {:error, :gap}
  true -> process_event(...)
end
```

---

## Envelope

The wire-level wrapper for all events.

```elixir
defmodule XTrack.IR.Envelope do
  @type t :: %__MODULE__{
    version: pos_integer(),    # Protocol version (currently 1)
    event_type: atom(),        # Event type identifier
    meta: EventMeta.t(),       # Event metadata
    payload: event()           # The actual event data
  }
  
  @type event ::
    RunStart.t() | RunEnd.t() |
    Param.t() | Metric.t() | MetricBatch.t() |
    Artifact.t() | Checkpoint.t() |
    StatusUpdate.t() | LogEntry.t() |
    Command.t() | Ack.t()
  
  @current_version 1
  
  defstruct [
    version: @current_version,
    :event_type,
    :meta,
    :payload
  ]
end
```

**Pattern Matching:**
```elixir
# Match specific event type
def handle(%Envelope{event_type: :metric, payload: %Metric{} = m}) do
  # Process metric
end

# Match any event
def handle(%Envelope{event_type: type, payload: payload}) do
  Logger.info("Received #{type}")
end
```

---

## Event Types

### RunStart

Initializes a new run with metadata.

```elixir
defmodule XTrack.IR.RunStart do
  @type t :: %__MODULE__{
    run_id: RunId.t(),
    name: String.t() | nil,
    tags: %{String.t() => String.t()},
    source: source_info() | nil,
    environment: env_info() | nil
  }

  @type source_info :: %{
    git_commit: String.t() | nil,
    git_branch: String.t() | nil,
    git_repo: String.t() | nil,
    entrypoint: String.t() | nil,
    code_hash: String.t() | nil
  }

  @type env_info :: %{
    python_version: String.t() | nil,
    platform: String.t() | nil,
    hostname: String.t() | nil,
    gpu_info: [map()] | nil,
    env_vars: %{String.t() => String.t()} | nil
  }

  defstruct [:run_id, :name, tags: %{}, source: nil, environment: nil]
end
```

**Fields:**

| Field | Purpose | Example |
|-------|---------|---------|
| `run_id` | Identity | `%RunId{id: "abc"}` |
| `name` | Human label | `"lr_sweep_0.001"` |
| `tags` | Filtering | `%{"model" => "resnet50"}` |
| `source` | Reproducibility | git info, code hash |
| `environment` | Debugging | Python version, GPU info |

---

### RunEnd

Signals run completion.

```elixir
defmodule XTrack.IR.RunEnd do
  @type t :: %__MODULE__{
    run_id: String.t(),
    status: :completed | :failed | :killed,
    error: error_info() | nil,
    final_metrics: %{String.t() => number()},
    duration_ms: non_neg_integer() | nil
  }

  @type error_info :: %{
    type: String.t(),
    message: String.t(),
    traceback: String.t() | nil
  }

  defstruct [:run_id, :status, :error, :duration_ms, final_metrics: %{}]
end
```

**Status Values:**

| Status | Meaning |
|--------|---------|
| `:completed` | Normal termination |
| `:failed` | Error occurred |
| `:killed` | External termination (SIGTERM, etc.) |

---

### Param

A hyperparameter or configuration value.

```elixir
defmodule XTrack.IR.Param do
  @type t :: %__MODULE__{
    run_id: String.t(),
    key: String.t(),
    value: param_value(),
    nested_key: [String.t()] | nil
  }
  
  @type param_value :: 
    number() | 
    String.t() | 
    boolean() | 
    [param_value()] | 
    %{String.t() => param_value()}
    
  defstruct [:run_id, :key, :value, :nested_key]
end
```

**Nested Parameters:**

For hierarchical config:
```python
{"optimizer": {"type": "adam", "lr": 0.001}}
```

Emitted as:
```elixir
%Param{key: "optimizer", value: "adam", nested_key: ["type"]}
%Param{key: "optimizer", value: 0.001, nested_key: ["lr"]}
```

Stored as:
```elixir
%{
  "optimizer.type" => "adam",
  "optimizer.lr" => 0.001
}
```

---

### Metric

A single metric measurement.

```elixir
defmodule XTrack.IR.Metric do
  @type t :: %__MODULE__{
    run_id: String.t(),
    key: String.t(),
    value: number(),
    step: non_neg_integer() | nil,
    epoch: non_neg_integer() | nil,
    context: metric_context()
  }

  @type metric_context :: %{
    phase: :train | :val | :test | nil,
    batch_size: non_neg_integer() | nil,
    dataset_size: non_neg_integer() | nil,
    aggregation: :mean | :sum | :last | nil
  }

  defstruct [:run_id, :key, :value, :step, :epoch, context: %{}]
end
```

**Indexing:**

Metrics are indexed by (run_id, key, step) for fast time-series queries:
```elixir
# Get loss over time
XTrack.get_metrics(run_id, "loss")
# => [%{step: 0, value: 2.5}, %{step: 100, value: 1.2}, ...]
```

---

### MetricBatch

Multiple metrics logged atomically.

```elixir
defmodule XTrack.IR.MetricBatch do
  @type t :: %__MODULE__{
    run_id: String.t(),
    step: non_neg_integer() | nil,
    epoch: non_neg_integer() | nil,
    metrics: %{String.t() => number()},
    context: Metric.metric_context()
  }

  defstruct [:run_id, :step, :epoch, :metrics, context: %{}]
end
```

**Use Case:**

Log all metrics for a step together:
```python
run.log_metrics({
    "loss": 0.5,
    "accuracy": 0.85,
    "lr": 0.001
}, step=1000)
```

This ensures all values share the same step/epoch.

---

### Artifact

A file artifact reference.

```elixir
defmodule XTrack.IR.Artifact do
  @type t :: %__MODULE__{
    run_id: String.t(),
    path: String.t(),
    artifact_type: artifact_type(),
    name: String.t() | nil,
    metadata: map(),
    size_bytes: non_neg_integer() | nil,
    checksum: String.t() | nil,
    upload_strategy: :inline | :reference | :stream
  }

  @type artifact_type :: 
    :model | :checkpoint | :weights | :config |
    :plot | :figure | :image |
    :data | :predictions | :embeddings |
    :log | :profile | :other

  defstruct [
    :run_id, :path, :artifact_type, :name,
    :size_bytes, :checksum,
    metadata: %{},
    upload_strategy: :reference
  ]
end
```

**Upload Strategies:**

| Strategy | Behavior |
|----------|----------|
| `:reference` | Store path only, file stays in place |
| `:inline` | (Future) Embed content in event |
| `:stream` | (Future) Stream via separate channel |

---

### Checkpoint

Training checkpoint with state.

```elixir
defmodule XTrack.IR.Checkpoint do
  @type t :: %__MODULE__{
    run_id: String.t(),
    step: non_neg_integer(),
    epoch: non_neg_integer() | nil,
    path: String.t(),
    metrics_snapshot: %{String.t() => number()},
    is_best: boolean(),
    best_metric_key: String.t() | nil,
    metadata: map()
  }

  defstruct [
    :run_id, :step, :epoch, :path, :best_metric_key,
    metrics_snapshot: %{},
    is_best: false,
    metadata: %{}
  ]
end
```

**Best Checkpoint Tracking:**

```python
# In training loop
is_best = val_loss < best_val_loss
if is_best:
    best_val_loss = val_loss

run.log_checkpoint(
    path=f"ckpt_{step}.pt",
    step=step,
    metrics={"val_loss": val_loss},
    is_best=is_best,
    best_metric_key="val_loss"
)
```

---

### StatusUpdate

Run status or progress update.

```elixir
defmodule XTrack.IR.StatusUpdate do
  @type t :: %__MODULE__{
    run_id: String.t(),
    status: status(),
    message: String.t() | nil,
    progress: progress() | nil
  }

  @type status :: 
    :initializing | :running | :training | :evaluating |
    :checkpointing | :paused | :resuming |
    :finishing | :completed | :failed | :killed

  @type progress :: %{
    current: non_neg_integer(),
    total: non_neg_integer(),
    unit: String.t()
  }

  defstruct [:run_id, :status, :message, :progress]
end
```

**Progress Reporting:**

```python
for epoch in range(10):
    run.set_status("training", 
        message=f"Epoch {epoch+1}/10",
        progress=(epoch+1, 10, "epochs"))
```

---

### LogEntry

Structured log message.

```elixir
defmodule XTrack.IR.LogEntry do
  @type t :: %__MODULE__{
    run_id: String.t(),
    level: :debug | :info | :warning | :error,
    message: String.t(),
    logger_name: String.t() | nil,
    step: non_neg_integer() | nil,
    fields: map()
  }

  defstruct [:run_id, :level, :message, :logger_name, :step, fields: %{}]
end
```

**Structured Fields:**

```python
run.log(
    "Training started",
    level="info",
    gpu_count=4,
    batch_size=128,
    distributed=True
)
```

Fields enable filtering and aggregation without parsing message text.

---

## Bidirectional Types

These types support control messages from collector to worker.

### Command

Control command to worker.

```elixir
defmodule XTrack.IR.Command do
  @type t :: %__MODULE__{
    command_id: String.t(),
    type: command_type(),
    payload: map()
  }

  @type command_type ::
    :pause | :resume | :stop | :checkpoint_now |
    :update_params | :adjust_lr | :custom

  defstruct [:command_id, :type, payload: %{}]
end
```

**Example Commands:**

```elixir
# Pause training
%Command{command_id: "cmd-1", type: :pause}

# Trigger checkpoint
%Command{command_id: "cmd-2", type: :checkpoint_now}

# Adjust learning rate
%Command{command_id: "cmd-3", type: :adjust_lr, payload: %{"lr" => 0.0001}}

# Custom application command
%Command{command_id: "cmd-4", type: :custom, payload: %{"action" => "snapshot_embeddings"}}
```

---

### Ack

Acknowledgment of received event.

```elixir
defmodule XTrack.IR.Ack do
  @type t :: %__MODULE__{
    seq: non_neg_integer(),
    status: :ok | :error,
    error_message: String.t() | nil
  }

  defstruct [:seq, :status, :error_message]
end
```

**Usage:**

For reliable delivery, collector can ack each event:
```elixir
# Success
%Ack{seq: 42, status: :ok}

# Failure
%Ack{seq: 42, status: :error, error_message: "Invalid metric value"}
```

---

## Type Conversions

### Wire → IR

The `XTrack.Wire` module handles JSON to IR conversion:

```elixir
# JSON map → Envelope
def map_to_envelope(%{"v" => v, "t" => t, "m" => m, "p" => p}) do
  %Envelope{
    version: v,
    event_type: String.to_existing_atom(t),
    meta: decode_meta(m),
    payload: decode_payload(event_type, p)
  }
end
```

### IR → Wire

```elixir
# Envelope → JSON map
def envelope_to_map(%Envelope{} = e) do
  %{
    "v" => e.version,
    "t" => Atom.to_string(e.event_type),
    "m" => encode_meta(e.meta),
    "p" => encode_payload(e.event_type, e.payload)
  }
end
```

### Storage Serialization

For Postgres storage, IR types are serialized to JSON:

```elixir
# Store
payload_json = envelope.payload |> Map.from_struct() |> Jason.encode!()

# Retrieve
payload_map = Jason.decode!(payload_json)
payload_struct = decode_payload(event_type, payload_map)
```

---

## Pattern Matching Examples

### Event Type Dispatch

```elixir
def handle_event(%Envelope{event_type: :metric, payload: m}) do
  update_metrics(m)
end

def handle_event(%Envelope{event_type: :param, payload: p}) do
  update_params(p)
end

def handle_event(%Envelope{event_type: :run_end, payload: r}) do
  finalize_run(r)
end

def handle_event(%Envelope{event_type: type}) do
  Logger.warning("Unhandled event type: #{type}")
end
```

### Selective Subscription

```elixir
# In LiveView
def handle_info({:xtrack_event, :metric, %Metric{key: "loss"} = m}, socket) do
  # Only handle loss metrics
  {:noreply, update_loss_chart(socket, m)}
end

def handle_info({:xtrack_event, :metric, _}, socket) do
  # Ignore other metrics
  {:noreply, socket}
end
```

### Guard Clauses

```elixir
def process_metric(%Metric{value: v}) when v < 0 do
  {:error, :negative_metric}
end

def process_metric(%Metric{} = m) do
  {:ok, m}
end
```
