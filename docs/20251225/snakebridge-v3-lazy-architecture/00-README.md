# SnakeBridge v3: Lazy Dynamic Architecture

**Date:** December 25, 2025
**Status:** Design Specification (Revised)
**Authors:** Architecture Team

---

## Executive Summary

SnakeBridge v3 introduces a paradigm shift from eager full-API generation to **lazy, demand-driven compilation**. Instead of generating complete adapters for entire Python libraries upfront, v3 builds only what developers actually use—accumulating bindings incrementally during development and caching them for production.

This architecture delivers:

- **10-100x faster compile times** for large libraries (sympy: seconds vs. minutes)
- **Zero configuration burden** for getting started
- **Smart documentation** that loads on-demand rather than building everything
- **Compile-time confidence** with real `.ex` source files
- **Deterministic builds** with environment locking
- **Ecosystem-ready design** for future hex_snake package registry

---

## Document Index

| Document | Description |
|----------|-------------|
| [01-vision-and-philosophy.md](./01-vision-and-philosophy.md) | Core principles and design philosophy |
| [02-configuration-system.md](./02-configuration-system.md) | mix.exs configuration with library versions |
| [03-lazy-compilation-engine.md](./03-lazy-compilation-engine.md) | Pre-pass generation architecture |
| [04-accumulator-cache.md](./04-accumulator-cache.md) | Source-based caching strategy |
| [05-documentation-system.md](./05-documentation-system.md) | Dynamic doc access without full generation |
| [06-pruning-system.md](./06-pruning-system.md) | Explicit cleanup and optimization |
| [07-developer-experience.md](./07-developer-experience.md) | UX flows and ergonomics |
| [08-ecosystem-vision.md](./08-ecosystem-vision.md) | hex_snake and future ecosystem |
| [09-implementation-roadmap.md](./09-implementation-roadmap.md) | Phased delivery plan |
| [10-migration-guide.md](./10-migration-guide.md) | v2 to v3 migration path |
| [11-engineering-decisions.md](./11-engineering-decisions.md) | Critical design decisions and rationale |

---

## Key Innovation: Pre-Pass Generation

**Critical Design Decision:** v3 uses a **pre-compilation generation pass**, NOT mid-compilation injection.

The pre-pass model generates real `.ex` source files before the Elixir compiler runs. This is fundamentally safer and more compatible with existing tooling than attempting to inject code mid-compilation.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      mix compile (orchestrated)                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               │               │
┌───────────────────────────┐      │               │
│  Phase 1: SnakeBridge     │      │               │
│  Compiler (runs first)    │      │               │
│                           │      │               │
│  1. Scan project AST      │      │               │
│  2. Detect library calls  │      │               │
│  3. Check manifest        │      │               │
│  4. Generate missing .ex  │      │               │
│  5. Update manifest       │      │               │
└───────────────────────────┘      │               │
                    │               │               │
                    ▼               │               │
┌───────────────────────────┐      │               │
│  Phase 2: Elixir Compiler │◄─────┘               │
│  (normal compilation)     │                      │
│                           │                      │
│  Compiles all .ex files   │                      │
│  including generated ones │                      │
└───────────────────────────┘                      │
                    │                              │
                    ▼                              │
┌───────────────────────────┐                      │
│  Phase 3: Verification    │◄─────────────────────┘
│  (optional)               │
│                           │
│  Dialyzer, tests, etc.    │
│  work normally            │
└───────────────────────────┘
```

---

## Why Pre-Pass, Not Mid-Compilation Injection?

The original v3 design proposed intercepting unresolved function calls during compilation and injecting code on-the-fly. After careful analysis, this approach was rejected:

| Aspect | Mid-Compilation Injection | Pre-Pass Generation |
|--------|--------------------------|---------------------|
| Compiler compatibility | Fragile, fights the compiler | Works with the compiler |
| Dialyzer | May complain about undefined functions | Normal static analysis |
| ExDoc | Incomplete or missing docs | Normal documentation |
| IDE support | "Go to definition" may fail | Works normally |
| Hot code reload | Undefined behavior | Normal semantics |
| Debugging | Complex, non-standard | Standard debugging |
| Concurrency | Requires locking, race-prone | Atomic file writes |

**The pre-pass model generates real `.ex` source files that the Elixir compiler processes normally.** This preserves all tooling benefits while still achieving lazy, demand-driven generation.

---

## Quick Comparison

| Aspect | v2 (Eager) | v3 (Lazy Pre-Pass) |
|--------|-----------|-----------|
| First compile of `sympy` | 45-90 seconds | 0.5 seconds |
| Functions generated | 481 (all) | 3 (only used) |
| Classes generated | 392 (all) | 0 (none used yet) |
| Cache type | BEAM (fragile) | Source `.ex` (portable) |
| Determinism | Version-dependent | Environment-locked |
| Tooling compatibility | Full | Full |
| Docs available | All upfront | On-demand lookup |

---

## Design Principles

1. **Pay for what you use** — Never generate code that won't be called
2. **Accumulate, don't regenerate** — Cache builds up over development
3. **Explicit over implicit cleanup** — Never delete generated code automatically
4. **Fast feedback loops** — Sub-second compile times are non-negotiable
5. **Compile-time confidence** — Generated code is real `.ex` source with specs and docs
6. **Deterministic builds** — Environment locking ensures reproducibility
7. **Docs are data, not artifacts** — Query Python directly for documentation
8. **Production-ready caches** — Dev cache becomes prod asset

---

## Getting Started (v3 Preview)

```elixir
# mix.exs
defp deps do
  [
    {:snakebridge, "~> 3.0",
     libraries: [
       numpy: "~> 1.26",
       pandas: "~> 2.0",
       sympy: "~> 1.12"
     ]}
  ]
end
```

That's it. No adapters config. No compile step. Just use the libraries:

```elixir
# Your code
Numpy.array([1, 2, 3])  # First compile triggers generation
Numpy.zeros({3, 3})     # Adds to cache
Pandas.read_csv(path)   # Different library, same pattern
```

First compile:
```
$ mix compile
SnakeBridge: Scanning project for library usage...
SnakeBridge: Generating Numpy.array/1, Numpy.zeros/1 (127ms)
SnakeBridge: Writing lib/snakebridge_generated/numpy.ex
Compiling 15 files (.ex)
```

Second compile:
```
$ mix compile
Compiling 0 files (.ex)
```

---

## Environment Locking

v3 introduces `snakebridge.lock` to ensure deterministic builds:

```json
{
  "version": "3.0.0",
  "generated_at": "2025-12-25T14:30:00Z",
  "environment": {
    "snakebridge_version": "3.0.0",
    "python_version": "3.11.5",
    "platform": "linux-x86_64",
    "elixir_version": "1.16.0",
    "otp_version": "26.1"
  },
  "libraries": {
    "numpy": {
      "requested": "~> 1.26",
      "resolved": "1.26.4",
      "checksum": "sha256:abc123..."
    }
  },
  "symbols": {
    "Numpy.array/1": {"generated_at": "..."},
    "Numpy.zeros/1": {"generated_at": "..."}
  }
}
```

When the environment changes, the lock file detects it and regenerates affected bindings.

---

## Next Steps

Read the documents in order, or jump to:

- **[03-lazy-compilation-engine.md](./03-lazy-compilation-engine.md)** — The core technical architecture
- **[11-engineering-decisions.md](./11-engineering-decisions.md)** — Why we made key choices
- **[07-developer-experience.md](./07-developer-experience.md)** — What it feels like to use
- **[08-ecosystem-vision.md](./08-ecosystem-vision.md)** — The bigger picture
