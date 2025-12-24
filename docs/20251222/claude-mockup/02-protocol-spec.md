# XTrack Protocol Specification

**Version:** 1  
**Status:** Stable

This document specifies the wire protocol for XTrack event transmission.

---

## Wire Format

### Framing

Events are transmitted as length-prefixed frames:

```
┌──────────────────┬────────────────────────────────────┐
│  Length (4 bytes)│           JSON Payload             │
│  big-endian u32  │         (Length bytes)             │
└──────────────────┴────────────────────────────────────┘
```

**Length:** 4-byte big-endian unsigned integer. Maximum value: 2^32 - 1 (~4GB).

**Payload:** UTF-8 encoded JSON. No trailing newline.

### Example

For the JSON `{"v":1,"t":"metric","m":{"seq":1,"ts":1703123456789000},"p":{"run_id":"abc","key":"loss","value":0.5}}`:

```
Bytes (hex): 00 00 00 5E 7B 22 76 22 3A 31 2C 22 74 22 3A ...
            ├─────────┤ ├─────────────────────────────────
            Length=94   JSON payload (94 bytes)
```

### Streaming

Multiple frames can be concatenated in a stream:

```
[Frame 1][Frame 2][Frame 3]...
```

Decoders should:
1. Read 4 bytes for length
2. Read `length` bytes for payload
3. Decode JSON
4. Repeat

Partial reads indicate:
- End of stream (clean)
- Connection dropped (error)
- Buffering needed (wait for more data)

---

## Envelope Schema

Every event is wrapped in an envelope:

```json
{
  "v": 1,
  "t": "event_type",
  "m": { /* metadata */ },
  "p": { /* payload */ }
}
```

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `v` | integer | yes | Protocol version (currently 1) |
| `t` | string | yes | Event type identifier |
| `m` | object | yes | Event metadata |
| `p` | object | yes | Event-specific payload |

### Metadata Object (`m`)

```json
{
  "seq": 42,
  "ts": 1703123456789000,
  "wid": "worker-0"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `seq` | integer | yes | Monotonically increasing sequence number within run |
| `ts` | integer | yes | Timestamp in microseconds since Unix epoch |
| `wid` | string | no | Worker identifier (for distributed training) |

**Sequence Numbers:**
- Start at 1 for `run_start`
- Increment by 1 for each event
- Gaps indicate lost events
- Duplicates should be ignored by collector

**Timestamps:**
- Microsecond precision
- Worker's local clock (not synchronized)
- Used for ordering within worker, not across workers

---

## Event Types

### run_start

Initializes a new experiment run.

**Type:** `"run_start"`

**Payload:**
```json
{
  "run_id": {
    "id": "uuid-string",
    "exp_id": "experiment-id",
    "parent_id": "parent-run-id"
  },
  "name": "human-readable-name",
  "tags": {"key": "value"},
  "source": {
    "git_commit": "abc123",
    "git_branch": "main",
    "git_repo": "https://github.com/...",
    "entrypoint": "train.py",
    "code_hash": "sha256:..."
  },
  "env": {
    "python_version": "3.11.0",
    "platform": "Linux-5.15.0-x86_64",
    "hostname": "worker-node-1",
    "gpu_info": [{"name": "A100", "memory": 40000000000}],
    "env_vars": {"CUDA_VISIBLE_DEVICES": "0,1"}
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `run_id` | object/string | yes | Run identifier (object with id/exp_id/parent_id, or just string) |
| `name` | string | no | Human-readable run name |
| `tags` | object | no | Key-value tags for filtering |
| `source` | object | no | Source control and code info |
| `env` | object | no | Runtime environment info |

**Notes:**
- `run_id` can be a simple string for backward compatibility
- If `run_id.id` not provided, collector generates one
- `source` and `env` are best-effort; missing fields are fine

---

### run_end

Signals run completion.

**Type:** `"run_end"`

**Payload:**
```json
{
  "run_id": "uuid-string",
  "status": "completed",
  "error": {
    "type": "RuntimeError",
    "message": "CUDA out of memory",
    "traceback": "Traceback (most recent call last):..."
  },
  "final_metrics": {"val_loss": 0.123, "val_acc": 0.95},
  "duration_ms": 3600000
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `run_id` | string | yes | Run identifier |
| `status` | string | yes | One of: `"completed"`, `"failed"`, `"killed"` |
| `error` | object | no | Error details (required if status is "failed") |
| `final_metrics` | object | no | Final metric values |
| `duration_ms` | integer | no | Total run duration in milliseconds |

---

### param

Logs a hyperparameter.

**Type:** `"param"`

**Payload:**
```json
{
  "run_id": "uuid-string",
  "key": "learning_rate",
  "value": 0.001,
  "nested_key": ["optimizer", "config"]
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `run_id` | string | yes | Run identifier |
| `key` | string | yes | Parameter name |
| `value` | any | yes | Parameter value (number, string, bool, array, object) |
| `nested_key` | array | no | Path for nested parameters |

**Nested Parameters:**

For hierarchical configs like:
```python
{"optimizer": {"type": "adam", "lr": 0.001}}
```

Emit as:
```json
{"key": "optimizer", "value": "adam", "nested_key": ["type"]}
{"key": "optimizer", "value": 0.001, "nested_key": ["lr"]}
```

Collector flattens to:
```
optimizer.type = "adam"
optimizer.lr = 0.001
```

---

### metric

Logs a single metric value.

**Type:** `"metric"`

**Payload:**
```json
{
  "run_id": "uuid-string",
  "key": "loss",
  "value": 0.5,
  "step": 1000,
  "epoch": 5,
  "ctx": {
    "phase": "train",
    "batch_size": 32,
    "dataset_size": 50000,
    "agg": "mean"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `run_id` | string | yes | Run identifier |
| `key` | string | yes | Metric name |
| `value` | number | yes | Metric value |
| `step` | integer | no | Training step/iteration |
| `epoch` | integer | no | Epoch number |
| `ctx` | object | no | Context information |

**Context Fields:**

| Field | Values | Description |
|-------|--------|-------------|
| `phase` | `"train"`, `"val"`, `"test"` | Training phase |
| `batch_size` | integer | Batch size used |
| `dataset_size` | integer | Total dataset size |
| `agg` | `"mean"`, `"sum"`, `"last"` | How value was aggregated |

---

### metric_batch

Logs multiple metrics atomically.

**Type:** `"metric_batch"`

**Payload:**
```json
{
  "run_id": "uuid-string",
  "step": 1000,
  "epoch": 5,
  "metrics": {
    "loss": 0.5,
    "accuracy": 0.85,
    "lr": 0.001
  },
  "ctx": {
    "phase": "train"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `run_id` | string | yes | Run identifier |
| `metrics` | object | yes | Key-value metric pairs |
| `step` | integer | no | Training step |
| `epoch` | integer | no | Epoch number |
| `ctx` | object | no | Context (same as metric) |

**Use Case:** Log all metrics for a step together, ensuring they share the same step/epoch.

---

### artifact

Registers a file artifact.

**Type:** `"artifact"`

**Payload:**
```json
{
  "run_id": "uuid-string",
  "path": "/absolute/path/to/model.pt",
  "type": "model",
  "name": "best_model",
  "meta": {
    "framework": "pytorch",
    "format": "state_dict"
  },
  "size": 1234567890,
  "checksum": "sha256:abc123...",
  "upload": "reference"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `run_id` | string | yes | Run identifier |
| `path` | string | yes | Absolute path to file |
| `type` | string | no | Artifact type (see below) |
| `name` | string | no | Logical name |
| `meta` | object | no | Artifact-specific metadata |
| `size` | integer | no | File size in bytes |
| `checksum` | string | no | SHA256 checksum |
| `upload` | string | no | Upload strategy |

**Artifact Types:**
- `"model"` - Trained model
- `"checkpoint"` - Training checkpoint
- `"weights"` - Model weights only
- `"config"` - Configuration file
- `"plot"` - Visualization
- `"figure"` - Figure/chart
- `"image"` - Image file
- `"data"` - Data file
- `"predictions"` - Model predictions
- `"embeddings"` - Vector embeddings
- `"log"` - Log file
- `"profile"` - Profiling data
- `"other"` - Anything else

**Upload Strategies:**
- `"reference"` - Path only, file stays in place
- `"inline"` - (Future) Base64 content in event
- `"stream"` - (Future) Separate upload channel

---

### checkpoint

Records a training checkpoint.

**Type:** `"checkpoint"`

**Payload:**
```json
{
  "run_id": "uuid-string",
  "step": 10000,
  "epoch": 10,
  "path": "/path/to/checkpoint_10.pt",
  "metrics": {
    "val_loss": 0.123,
    "val_acc": 0.95
  },
  "is_best": true,
  "best_key": "val_loss",
  "meta": {
    "optimizer_state": true,
    "scheduler_state": true
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `run_id` | string | yes | Run identifier |
| `step` | integer | yes | Training step |
| `path` | string | yes | Path to checkpoint file |
| `epoch` | integer | no | Epoch number |
| `metrics` | object | no | Metrics at checkpoint time |
| `is_best` | boolean | no | Whether this is the best checkpoint |
| `best_key` | string | no | Metric key used for "best" determination |
| `meta` | object | no | Additional metadata |

---

### status

Updates run status or progress.

**Type:** `"status"`

**Payload:**
```json
{
  "run_id": "uuid-string",
  "status": "training",
  "msg": "Epoch 5/10",
  "progress": {
    "cur": 5,
    "total": 10,
    "unit": "epochs"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `run_id` | string | yes | Run identifier |
| `status` | string | yes | Status value (see below) |
| `msg` | string | no | Human-readable message |
| `progress` | object | no | Progress information |

**Status Values:**
- `"initializing"` - Setting up
- `"running"` - Active (generic)
- `"training"` - Training phase
- `"evaluating"` - Evaluation phase
- `"checkpointing"` - Saving checkpoint
- `"paused"` - Temporarily paused
- `"resuming"` - Resuming from pause
- `"finishing"` - Cleaning up
- `"completed"` - Done successfully
- `"failed"` - Terminated with error
- `"killed"` - Terminated externally

**Progress Object:**

| Field | Type | Description |
|-------|------|-------------|
| `cur` | integer | Current position |
| `total` | integer | Total count |
| `unit` | string | Unit label ("epochs", "steps", "samples", etc.) |

---

### log

Structured log message.

**Type:** `"log"`

**Payload:**
```json
{
  "run_id": "uuid-string",
  "level": "info",
  "msg": "Starting training with 4 GPUs",
  "logger": "train.distributed",
  "step": 0,
  "fields": {
    "gpu_count": 4,
    "batch_size": 128
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `run_id` | string | yes | Run identifier |
| `level` | string | yes | Log level |
| `msg` | string | yes | Log message |
| `logger` | string | no | Logger name |
| `step` | integer | no | Training step |
| `fields` | object | no | Structured fields |

**Log Levels:**
- `"debug"`
- `"info"`
- `"warning"`
- `"error"`

---

## Bidirectional Events (Optional)

These events flow from collector to worker. They are optional and require transport support.

### command

Control command to worker.

**Type:** `"command"`

**Payload:**
```json
{
  "cmd_id": "uuid-string",
  "type": "pause",
  "payload": {}
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `cmd_id` | string | yes | Command identifier |
| `type` | string | yes | Command type |
| `payload` | object | no | Command-specific data |

**Command Types:**
- `"pause"` - Pause training
- `"resume"` - Resume training
- `"stop"` - Stop gracefully
- `"checkpoint_now"` - Trigger checkpoint
- `"update_params"` - Update hyperparameters (payload contains new values)
- `"adjust_lr"` - Adjust learning rate (payload: `{"lr": 0.0001}`)
- `"custom"` - Application-defined (payload: anything)

### ack

Acknowledgment from collector.

**Type:** `"ack"`

**Payload:**
```json
{
  "seq": 42,
  "status": "ok",
  "error": null
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `seq` | integer | yes | Sequence number being acknowledged |
| `status` | string | yes | `"ok"` or `"error"` |
| `error` | string | no | Error message if status is "error" |

---

## Protocol Evolution

### Version Negotiation

Currently not implemented. Future versions may add:

1. **Capability exchange** in `run_start` response
2. **Feature flags** in envelope
3. **Downgrade support** for older collectors

### Backward Compatibility

Version 1 guarantees:

1. **Unknown fields ignored.** Collectors must ignore fields they don't recognize.
2. **Unknown events logged.** Unknown event types are logged but don't error.
3. **Payload changes are additive.** New fields can be added; existing fields won't change meaning.

### Breaking Changes

These would require version 2:

1. Removing required fields
2. Changing field semantics
3. Changing framing format
4. Changing envelope structure

---

## Implementation Notes

### Python Emitter

```python
# Encoding
def encode_frame(envelope: dict) -> bytes:
    json_bytes = json.dumps(envelope, separators=(',', ':')).encode('utf-8')
    length = len(json_bytes)
    return struct.pack('>I', length) + json_bytes

# Sending
def emit(event_type: str, payload: dict, seq: int):
    envelope = {
        "v": 1,
        "t": event_type,
        "m": {"seq": seq, "ts": int(time.time() * 1_000_000)},
        "p": payload
    }
    frame = encode_frame(envelope)
    transport.send(frame)
```

### Elixir Decoder

```elixir
# Decoding
def decode_frame(<<len::big-unsigned-32, rest::binary>>) when byte_size(rest) >= len do
  <<json::binary-size(len), remaining::binary>> = rest
  {:ok, map} = Jason.decode(json)
  {:ok, map_to_envelope(map), remaining}
end

def decode_frame(data) when byte_size(data) < 4 do
  {:incomplete, 4 - byte_size(data)}
end
```

### Error Handling

Decoders should handle:

1. **Incomplete frames** - Buffer and wait
2. **Invalid JSON** - Log error, discard frame, resync
3. **Missing required fields** - Return error
4. **Unknown event types** - Log warning, skip event
5. **Invalid field values** - Return error

Resync strategy for corrupted streams:
1. Scan for valid length prefix (4 bytes that form reasonable length)
2. Try to decode JSON
3. If success, continue from there
4. If fail, advance by 1 byte and repeat
