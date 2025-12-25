# Roadmap: Phased Implementation

This plan assumes a staged rollout with high-value features first.

## Phase 0: Alignment (Now)

- Finalize config schema in mix.exs
- Pick the canonical execution model (deterministic prepass)
- Define lockfile format and environment identity
- Define manifest/ledger formats and file locking rules
- Lock down file locations and cache strategy

## Phase 1: Lazy Generation MVP

- AST scanner for symbol usage
- Stub module generation
- Incremental generator updates
- Deterministic `snakebridge.lock` updates
- `mix snakepit.prune` (manual only)
- `mix snakepit.promote_ledger` (manual ledger promotion)

**Success criteria**: For SymPy, initial compile produces a few dozen files, not thousands.

## Phase 2: On-Demand Docs

- Search index generation from metadata
- `mix snakepit.docs` CLI
- IEx docs API (`Snakepit.doc/1` and `Snakepit.search/2`)
- HTML caching and portal

**Success criteria**: First doc page render under 200 ms on a warm cache.

## Phase 3: Registry and Packaging

- `mix snakepit.pack` to generate metadata packages
- Registry resolution strategy in compile task
- Publish initial core library metadata

**Success criteria**: Common libraries install without local introspection.

## Phase 4: Advanced UX

- Agent-first APIs for programmatic usage
- Per-library pool tuning
- Multi-project cache sharing
- Experimental tracer (only if it can be made deterministic)
