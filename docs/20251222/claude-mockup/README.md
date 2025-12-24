# XTrack Documentation

Cross-language ML experiment tracking protocol for Elixir ↔ Python.

## Documents

| Document | Purpose | Audience |
|----------|---------|----------|
| [01-architecture.md](01-architecture.md) | Design philosophy, system layers, component deep-dive | Developers, architects |
| [02-protocol-spec.md](02-protocol-spec.md) | Wire format, event schemas, protocol details | Implementers, debuggers |
| [03-ir-reference.md](03-ir-reference.md) | Elixir type definitions, pattern matching examples | Elixir developers |
| [04-workflows.md](04-workflows.md) | Common use cases, code patterns | Users, integrators |
| [05-integrations.md](05-integrations.md) | Framework and system integrations | DevOps, ML engineers |
| [06-development.md](06-development.md) | Implementation notes, future work | Contributors |

## Quick Navigation

### I want to...

**Understand the system**
→ Start with [Architecture](01-architecture.md)

**Implement a client in another language**
→ Read [Protocol Spec](02-protocol-spec.md)

**Write Elixir code that handles events**
→ See [IR Reference](03-ir-reference.md)

**Track my PyTorch training**
→ See [Workflows](04-workflows.md#pytorch)

**Deploy on Kubernetes**
→ See [Integrations](05-integrations.md#kubernetes)

**Contribute to XTrack**
→ Read [Development Notes](06-development.md)

## Core Concepts

### The Insight

Traditional ML tracking (MLflow, W&B) runs as separate services because Python can't hold state reliably. XTrack inverts this: **Elixir is the control plane**, Python just emits events.

### The Stack

```
┌─────────────────────────────────┐
│     Your Application            │  LiveView, CLI, pipelines
├─────────────────────────────────┤
│     XTrack Runtime              │  Collectors, storage, PubSub
├─────────────────────────────────┤
│     Protocol Layer              │  IR types, wire encoding
├─────────────────────────────────┤
│     Python Workers              │  Training code with xtrack
└─────────────────────────────────┘
```

### Key Types

| Type | Purpose |
|------|---------|
| `Envelope` | Wire wrapper with version, type, metadata |
| `EventMeta` | Sequence number, timestamp, worker ID |
| `Metric` | Single metric value with step/epoch |
| `Param` | Hyperparameter with nested key support |
| `Checkpoint` | Training checkpoint with metrics snapshot |
| `Artifact` | File reference with type and metadata |

### Event Flow

```
Python                    Wire                     Elixir
───────                   ────                     ──────
run.log_metric()    →    JSON frame    →    Collector.push_event()
                                                    ↓
                                             Update state
                                                    ↓
                                             PubSub broadcast
                                                    ↓
                                             Storage persist
```

## File Structure

```
xtrack/
├── lib/
│   ├── xtrack.ex                 # Main API
│   └── xtrack/
│       ├── ir.ex                 # Type definitions
│       ├── wire.ex               # Protocol encoding
│       ├── collector.ex          # Event processing
│       ├── transport.ex          # Port, TCP, file
│       ├── run_manager.ex        # Supervision
│       └── storage.ex            # ETS, Postgres
├── python/
│   └── xtrack/
│       └── __init__.py           # Python emitter
├── docs/                         # This documentation
└── examples/
    └── complete_example.exs      # Usage examples
```

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2024-12 | Initial protocol specification |

## Contributing

1. Read [Development Notes](06-development.md)
2. Check existing issues
3. Open PR with tests
4. Update docs if needed
