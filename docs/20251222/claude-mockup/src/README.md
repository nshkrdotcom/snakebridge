# XTrack - Cross-Language ML Experiment Tracking Protocol

A transport-agnostic protocol and IR for ML experiment tracking between Elixir and Python (or any language pair).

## Design Principles

1. **Transport Agnostic** - Works over stdio, TCP, Unix sockets, or embedded (NIF/Port)
2. **Minimal Python Dependencies** - stdlib only on Python side
3. **Typed IR** - Strongly typed on both sides with clear serialization
4. **Unidirectional Events** - Python emits, Elixir collects (with optional acks)
5. **Idempotent** - Events carry enough context to dedupe/replay

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Elixir (Control Plane)                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   Collector  │  │   Decoder    │  │   Run Manager    │  │
│  │  (GenServer) │◄─┤  (Protocol)  │◄─┤   (Supervisor)   │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
└─────────────────────────────┬───────────────────────────────┘
                              │ Wire Protocol (JSON + framing)
                              │
┌─────────────────────────────┴───────────────────────────────┐
│                    Python (Compute Worker)                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   Emitter    │──►│   Encoder    │──►│    Transport    │  │
│  │   (API)      │  │   (Wire)     │  │   (stdio/tcp)   │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Event Types

### From Python → Elixir

| Event | Purpose |
|-------|---------|
| `run_started` | Initialize a new experiment run |
| `param` | Log a hyperparameter |
| `metric` | Log a metric value (loss, accuracy, etc.) |
| `artifact` | Register an artifact (model file, plot, etc.) |
| `checkpoint` | Signal a checkpoint was saved |
| `log` | Structured log message |
| `status` | Status update (training, evaluating, etc.) |
| `run_finished` |