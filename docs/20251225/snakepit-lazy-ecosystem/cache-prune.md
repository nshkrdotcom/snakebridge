# Cache and Prune Strategy

The lazy architecture depends on durable caches and explicit pruning. This document defines the cache layers and deletion policies.

## Cache Layers

1. **Python Package Cache**
   - Managed by uv or pip
   - Location: `priv/snakepit/python` (configurable)
   - Purpose: avoid repeated downloads and installations

2. **Introspection Metadata Cache**
   - JSON snapshots for each library
   - Location: `priv/snakepit/metadata`
   - Purpose: stable inputs for code generation

3. **Adapter Source Cache**
   - Generated `.ex` files
   - Location: `lib/snakebridge_generated/`
   - Purpose: compile-time tooling and runtime API

4. **Docs Cache**
   - Per-symbol HTML files and search index
   - Location: `priv/snakepit/docs`
   - Purpose: fast docs without full rebuild

## Manifest and Ledger

Each library maintains:

- **Manifest**: list of generated symbols
- **Ledger**: record of symbol usage (compile or runtime)

The ledger is append-only; the manifest is the source of truth for what exists in the generated code.

## Pruning Policy

Default behavior is **no pruning**. This avoids surprising deletions and reduces diff churn.

### Manual Prune

```
mix snakepit.prune --library sympy
```

This command:

- recomputes used symbols based on current source
- compares to manifest
- deletes unused adapters

### Auto Prune (Opt-in)

When `prune: :auto` is set, unused wrappers are removed during compile. This is for teams who value minimal code size over stable diffs.

## Cache Sharing (CI and Teams)

- Metadata and docs caches can be stored in a shared cache dir
- Adapter source may be checked into git for deterministic builds
- Usage ledger should be considered local and ephemeral

## Failure Modes

- **Missing cache**: regenerate from metadata or re-introspect
- **Stale metadata**: regenerate and update manifest hash
- **Library version change**: invalidate manifest and regenerate

