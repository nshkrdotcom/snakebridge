# Vision and Philosophy

## The Problem with Eager Generation

SnakeBridge v2 works like this:

1. Developer configures `adapters: [:numpy, :sympy]`
2. `mix compile` runs Python introspection on entire libraries
3. Generates complete Elixir modules for every function and class
4. Developer waits 30-90 seconds for sympy alone
5. 99% of generated code is never used

This is backwards. We're doing expensive work upfront that may never pay off.

## The Lazy Philosophy

> "The best code is the code you never had to write."

SnakeBridge v3 inverts the model:

1. Developer declares library dependencies with versions
2. Compilation proceeds normally—no generation step
3. When code references `Numpy.array/1`, that function is generated
4. Generated code is cached for future compiles
5. Only used functions ever exist

This is **demand-driven compilation**—the same philosophy behind:
- Haskell's lazy evaluation
- JIT compilers
- Modern JavaScript bundlers (tree-shaking)
- Database query optimization (only fetch needed columns)

## Core Principles

### 1. Pay-Per-Use Compilation

Every generated function has a cost:
- Introspection time
- Code generation time
- Compile time
- Disk space
- Documentation build time

In v2, this cost is paid upfront for everything. In v3, you pay only for what you use.

**Example:** Using 5 numpy functions in a project:

| Approach | Functions Generated | Time |
|----------|-------------------|------|
| v2 Eager | 1,500+ | 15 sec |
| v3 Lazy | 5 | 0.3 sec |

### 2. Accumulative Cache

Development is iterative. As you write code, you naturally use more of a library over time.

```
Day 1: Numpy.array, Numpy.zeros           → 2 functions cached
Day 2: + Numpy.dot, Numpy.reshape         → 4 functions cached
Day 3: + Numpy.linalg.solve               → 5 functions cached
Week 2: + 10 more functions               → 15 functions cached
```

The cache **only grows**. We never automatically remove anything because:
- Removal could break builds
- "Unused" code might be used in tests
- Dead code elimination is a separate concern

### 3. Explicit Pruning

While the cache accumulates by default, developers can explicitly prune:

```bash
# See what's unused
mix snakebridge.analyze

# Prune with confirmation
mix snakebridge.prune --dry-run
mix snakebridge.prune

# Per-library control
mix snakebridge.prune numpy --keep-last-used 30d
```

This can also be configured for CI:

```elixir
# config/config.exs
config :snakebridge,
  auto_prune: [
    enabled: true,
    keep_days: 30,
    environment: :prod  # Only prune in prod builds
  ]
```

### 4. Documentation as Query

Traditional approach:
```
Generate docs for 1000 functions → Build ExDoc → Hope dev finds what they need
```

v3 approach:
```
Developer asks for docs → Query Python → Return docs → Cache for speed
```

This is fundamentally different. Instead of building a complete documentation artifact, we treat docs as a queryable data source:

```elixir
# IEx session
iex> Numpy.doc(:array)
"""
numpy.array(object, dtype=None, ...)

Create an array.

Parameters
----------
object : array_like
    An array, any object exposing the array interface...
"""

iex> Numpy.search("linear algebra")
[
  {:linalg_solve, "Solve a linear matrix equation"},
  {:linalg_inv, "Compute the inverse of a matrix"},
  ...
]
```

### 5. Version-Locked Dependencies

Python library versions matter. `numpy 1.26` has different APIs than `numpy 2.0`. v3 treats Python libraries as first-class versioned dependencies:

```elixir
{:snakebridge, "~> 3.0",
 libraries: [
   numpy: "~> 1.26",    # Uses UV to install exact version
   pandas: "~> 2.0"
 ]}
```

This ensures:
- Reproducible builds
- Correct introspection for the version you're using
- No surprises when library APIs change

### 6. Zero-Config Start

The barrier to using a Python library should be one line:

```elixir
{:snakebridge, "~> 3.0", libraries: [numpy: "~> 1.26"]}
```

No additional configuration needed. No manual steps. No "run this mix task first".

## The Development Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Developer Experience                         │
└─────────────────────────────────────────────────────────────────────┘

  1. Add dependency
     ┌────────────────────────────────────────────────────────────┐
     │ {:snakebridge, "~> 3.0", libraries: [numpy: "~> 1.26"]}   │
     └────────────────────────────────────────────────────────────┘
                                │
                                ▼
  2. Write code naturally
     ┌────────────────────────────────────────────────────────────┐
     │ result = Numpy.array([1, 2, 3]) |> Numpy.sum()            │
     └────────────────────────────────────────────────────────────┘
                                │
                                ▼
  3. Compile (sub-second, generates only Numpy.array and Numpy.sum)
     ┌────────────────────────────────────────────────────────────┐
     │ $ mix compile                                              │
     │ Compiling 1 file (.ex)                                     │
     │ SnakeBridge: Generated Numpy.array/1, Numpy.sum/1         │
     └────────────────────────────────────────────────────────────┘
                                │
                                ▼
  4. Run, test, iterate
     ┌────────────────────────────────────────────────────────────┐
     │ $ mix test                                                 │
     │ .....                                                      │
     │ 5 tests, 0 failures                                        │
     └────────────────────────────────────────────────────────────┘
                                │
                                ▼
  5. Deploy (cache is compiled into release)
     ┌────────────────────────────────────────────────────────────┐
     │ $ mix release                                              │
     │ Release my_app-0.1.0 created                               │
     └────────────────────────────────────────────────────────────┘
```

## What This Enables

### For Individual Developers
- Instant feedback loop
- No waiting for libraries you barely use
- Documentation at your fingertips

### For Teams
- Consistent builds (version-locked Python deps)
- Shared caches (optional team cache server)
- Clear visibility into what Python is actually used

### For the Ecosystem
- Foundation for pre-built caches (hex_snake)
- Community-shared type hints
- Crowdsourced documentation improvements

## Philosophy Summary

| Old Way | New Way |
|---------|---------|
| Generate everything upfront | Generate on demand |
| Wait for initial setup | Start immediately |
| Docs as build artifact | Docs as live query |
| Hope you use what's generated | Know you use what's generated |
| Manual cleanup | Explicit, controlled pruning |
| Library versions implicit | Library versions explicit |

This isn't just an optimization—it's a different mental model. SnakeBridge v3 treats Python libraries as **living dependencies** that reveal themselves as needed, not **static artifacts** that must be fully materialized.
