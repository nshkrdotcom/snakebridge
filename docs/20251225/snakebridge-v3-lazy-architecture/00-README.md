# SnakeBridge v3: Lazy Dynamic Architecture

**Date:** December 25, 2025
**Status:** Design Specification
**Authors:** Architecture Team

---

## Executive Summary

SnakeBridge v3 introduces a paradigm shift from eager full-API generation to **lazy, demand-driven compilation**. Instead of generating complete adapters for entire Python libraries upfront, v3 builds only what developers actually use—accumulating bindings incrementally during development and caching them for production.

This architecture delivers:

- **10-100x faster compile times** for large libraries (sympy: seconds vs. minutes)
- **Zero configuration burden** for getting started
- **Smart documentation** that loads on-demand rather than building everything
- **Ecosystem-ready design** for future hex_snake package registry

---

## Document Index

| Document | Description |
|----------|-------------|
| [01-vision-and-philosophy.md](./01-vision-and-philosophy.md) | Core principles and design philosophy |
| [02-configuration-system.md](./02-configuration-system.md) | mix.exs configuration with library versions |
| [03-lazy-compilation-engine.md](./03-lazy-compilation-engine.md) | Demand-driven compilation architecture |
| [04-accumulator-cache.md](./04-accumulator-cache.md) | Incremental caching strategy |
| [05-documentation-system.md](./05-documentation-system.md) | Dynamic doc access without full generation |
| [06-pruning-system.md](./06-pruning-system.md) | Explicit cleanup and optimization |
| [07-developer-experience.md](./07-developer-experience.md) | UX flows and ergonomics |
| [08-ecosystem-vision.md](./08-ecosystem-vision.md) | hex_snake and future ecosystem |
| [09-implementation-roadmap.md](./09-implementation-roadmap.md) | Phased delivery plan |
| [10-migration-guide.md](./10-migration-guide.md) | v2 to v3 migration path |

---

## Key Innovation: The Compilation Observer

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Developer writes code                           │
│                                                                         │
│   defmodule MyApp do                                                    │
│     def calculate do                                                    │
│       Numpy.array([1, 2, 3])        ◄── Compiler sees this call        │
│       |> Numpy.dot(other)           ◄── And this one                    │
│     end                                                                 │
│   end                                                                   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    SnakeBridge Compilation Observer                     │
│                                                                         │
│   1. Intercepts references to Numpy.array/1 and Numpy.dot/2            │
│   2. Checks cache: these functions already generated? ──► Use cache    │
│   3. If not: introspect Python for JUST these functions                │
│   4. Generate minimal bindings                                          │
│   5. Add to accumulator cache                                           │
│   6. Compile continues with generated code available                    │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Quick Comparison

| Aspect | v2 (Eager) | v3 (Lazy) |
|--------|-----------|-----------|
| First compile of `sympy` | 45-90 seconds | 0.5 seconds |
| Functions generated | 481 (all) | 3 (only used) |
| Classes generated | 392 (all) | 0 (none used yet) |
| Disk usage | 15MB+ | 50KB |
| Docs available | All upfront | On-demand lookup |
| Developer friction | Wait for full gen | Instant feedback |

---

## Design Principles

1. **Pay for what you use** — Never generate code that won't be called
2. **Accumulate, don't regenerate** — Cache builds up over development
3. **Explicit over implicit cleanup** — Never delete generated code automatically
4. **Fast feedback loops** — Sub-second compile times are non-negotiable
5. **Docs are data, not artifacts** — Query Python directly for documentation
6. **Production-ready caches** — Dev cache becomes prod asset

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
Numpy.array([1, 2, 3])  # First use triggers generation
Numpy.zeros({3, 3})     # Adds to cache
Pandas.read_csv(path)   # Different library, same pattern
```

---

## Next Steps

Read the documents in order, or jump to:

- **[03-lazy-compilation-engine.md](./03-lazy-compilation-engine.md)** — The core technical innovation
- **[07-developer-experience.md](./07-developer-experience.md)** — What it feels like to use
- **[08-ecosystem-vision.md](./08-ecosystem-vision.md)** — The bigger picture

