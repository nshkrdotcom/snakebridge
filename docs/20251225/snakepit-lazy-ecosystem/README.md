# Snakepit Lazy Ecosystem (2025-12-25)

**Status**: Vision and architecture baseline
**Audience**: Snakepit and Snakebridge maintainers, library authors, ML platform teams

This document set defines the 2025-12-25 vision for a new Snakepit + Snakebridge ecosystem: a lazy, cached, developer-first bridge to Python libraries where setup is near-zero, adapters are generated only for what you use, and documentation is available on demand instead of being fully rendered upfront.

## Executive Summary

The current model generates full adapters and full docs for every library. That is accurate but expensive and heavy, especially for large libraries like SymPy or SciPy. The new model flips the default and removes compile-time magic:

- **Only generate what you use** (incrementally, cached, never pruning unless asked)
- **Configure libraries where you already configure Snakepit** (mix.exs dependency block)
- **Make runtime setup automatic** (Python environment, uv installs, worker lifecycle)
- **Provide docs on demand** (searchable, cached, partial HTML and IEx-first)
- **Deterministic build identity** (lockfile, environment identity, reproducible adapters)

The result is a faster, lighter developer experience that still grows into completeness as real usage expands.

## Design Principles

1. **Progressive Disclosure**: Start minimal, become comprehensive as the codebase actually uses more of a library.
2. **No Unwanted Churn**: Once generated, code stays until explicitly pruned. Diffs should be stable.
3. **Setup Should Be Invisible**: Snakepit handles Python environment and dependencies; the user only declares libraries.
4. **Docs Are a Product**: Documentation should be accessible in small, fast slices, not only as a huge batch export.
5. **Compile-Time Confidence**: Generated code must be real `.ex` source with specs and docs, not runtime magic.
6. **Cache Is Durable**: Cache is an asset that speeds future builds and is safe to commit or share.
7. **Agent-Friendly**: The system should be introspectable and callable by automation and AI agents.

## Architecture at a Glance

```
User mix.exs
  {:snakepit, "~> 0.4.0",
   snakebridge: [
     libraries: [sympy: "1.12", numpy: "1.26"],
     lazy_generation: :on,
     prune: :manual,
     docs: :on_demand,
     lockfile: "snakebridge.lock"
   ]}

mix compile (prepass)
  - Create library stubs so modules exist
  - Scan project AST for calls
  - Resolve symbols via metadata snapshot
  - Generate missing wrappers to lib/snakebridge_generated/
  - Update snakebridge.lock deterministically

Runtime
  - Snakepit starts automatically
  - Generated wrappers call Snakepit.execute/3
  - Dynamic calls go through Snakepit.dynamic_call/4

Docs
  - Search index built from metadata snapshot
  - Optional live-doc query in dev
  - Per-symbol HTML rendered on demand
```

## Developer Journey (60-second view)

1. Add Snakepit dependency with libraries list in `mix.exs`.
2. `mix compile` runs a prepass that generates only the adapters you used.
3. Use `Library.__functions__/0` and `Library.__search__/1` during exploration.
4. Need docs? `mix snakepit.docs sympy.integrate` or `Snakepit.doc/1`.
5. When you intentionally want to shrink, run `mix snakepit.prune`.

## Doc Set Map

- `vision.md`: high-level narrative and product posture
- `ux-journeys.md`: developer workflows and experience targets
- `config-spec.md`: mix.exs schema and library configuration details
- `compiler-strategy.md`: deterministic prepass, stubs, and generation lifecycle
- `lazy-generation.md`: how usage detection and incremental generation work
- `cache-prune.md`: caching model, invalidation, pruning policies
- `determinism-lockfile.md`: environment identity, lockfile format, merge strategy
- `docs-experience.md`: on-demand docs system and HTML rendering strategy
- `agentic-workflows.md`: programmatic discovery and adapter generation for agents
- `runtime-architecture.md`: Snakepit startup, worker pool, and runtime API
- `ecosystem-registry.md`: library metadata registry and packaging strategy
- `roadmap.md`: phased implementation plan and milestones
- `open-questions.md`: unresolved issues and decision points

## What Is New and Meaningful

- **Library configs live with Snakepit** so users configure runtime and adapters together.
- **Lazy generation** for function wrappers based on real usage signals.
- **On-demand docs** with search-first access and per-symbol HTML rendering.
- **Pruning is explicit**, not implicit, to avoid surprising deletions.
- **Agentic workflows** can programmatically ask for symbol docs or adapters.
- **Lockfile and environment identity** make adapter generation reproducible.

## Success Metrics

- First compile time for large libraries under 15 seconds on common dev machines.
- `mix docs` time independent of library size; on-demand docs under 200 ms per symbol.
- Zero manual Python setup for 95 percent of user installs.
- Adapter generation file churn under 5 percent per change outside of explicit prune.
