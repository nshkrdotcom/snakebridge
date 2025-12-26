# SnakeBridge v3 Architecture

> Canonical design for lazy, deterministic Python library bindings in Elixir

## Executive Summary

SnakeBridge v3 is a **compile-time code generator** that produces type-safe Elixir adapters for Python libraries. It uses **lazy pre-pass generation**—only generating bindings for functions actually used in your codebase—with **deterministic, reproducible builds**.

**Key architectural decision**: SnakeBridge is the codegen layer; [Snakepit](https://hex.pm/packages/snakepit) remains the runtime substrate for Python process management.

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Build Time (mix compile)                            │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                   │
│  1. SnakeBridge Compiler (runs FIRST)                                            │
│     ┌────────────┐    ┌─────────────┐    ┌────────────┐    ┌────────────────────┐│
│     │  Scanner   │───►│ Introspector│───►│ Generator  │───►│ lib/snakebridge_   ││
│     │ (AST walk) │    │  (Python)   │    │ (.ex files)│    │ generated/*.ex     ││
│     └────────────┘    └─────────────┘    └────────────┘    └────────────────────┘│
│           │                                                         │             │
│           ▼                                                         ▼             │
│     Reads your         Queries Python for                    Written to git,     │
│     source files       signatures, docs                      compiled normally   │
│                                                                                   │
│  2. Elixir Compiler (normal)                                                      │
│     └── Compiles all .ex including generated                                     │
│                                                                                   │
│  3. Release/Deployment                                                            │
│     └── No Python needed - generated source is committed                         │
│                                                                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│                              Run Time                                            │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                   │
│  Generated modules call through Snakepit runtime:                                │
│                                                                                   │
│  ┌────────────┐    ┌──────────────┐    ┌──────────────┐    ┌────────────────────┐│
│  │Numpy.array │───►│ SnakeBridge  │───►│   Snakepit   │───►│  Python Process    ││
│  │   (call)   │    │   Runtime    │    │ gRPC Pool    │    │  (numpy.array)     ││
│  └────────────┘    └──────────────┘    └──────────────┘    └────────────────────┘│
│                                                                                   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Core Principles

### 1. Lazy Generation (Only What You Use)

```elixir
# Your code uses 3 numpy functions
defmodule MyApp.Analysis do
  def run(data) do
    {:ok, arr} = Numpy.array(data)
    {:ok, mean} = Numpy.mean(arr)
    {:ok, std} = Numpy.std(arr)
    {mean, std}
  end
end

# SnakeBridge only generates:
#   - Numpy.array/1
#   - Numpy.mean/1  
#   - Numpy.std/1
# NOT the 800+ other numpy functions
```

### 2. Deterministic Builds

- **Source caching** - Generated `.ex` files are committed to git
- **Lock file** - Environment identity (Python version, library versions)
- **Sorted output** - Alphabetical keys for minimal merge conflicts
- **No timestamps in output** - Content-addressed, not time-addressed

### 3. Append-Only Accumulation

- Cache only grows; never auto-deletes
- Pruning is an **explicit developer action**
- Determinism over automation

### 4. Separation of Concerns

| Layer | Package | Responsibility |
|-------|---------|----------------|
| Codegen | SnakeBridge | Scanning, introspection, generation |
| Runtime | Snakepit | Process pooling, gRPC, execution |

## File Structure

```
my_app/
├── mix.exs                              # {:snakebridge, libraries: [...]}
├── lib/
│   ├── my_app/                          # Your code
│   │   └── analysis.ex                  # Uses Numpy.array, Numpy.mean
│   └── snakebridge_generated/           # Generated source (committed to git)
│       ├── numpy.ex                     # All generated Numpy functions
│       ├── pandas.ex                    # All generated Pandas functions
│       └── sympy.ex                     # All generated Sympy functions
├── .snakebridge/
│   ├── manifest.json                    # Symbol tracking (committed)
│   ├── scan_cache.json                  # File hash cache (local)
│   └── ledger.json                      # Dynamic call log (dev only, not committed)
├── snakebridge.lock                     # Environment lock (committed)
└── _build/                              # Compiled BEAM (not committed)
```

## Generation Pipeline

### Phase 1: Scan

The AST scanner walks your project source (`lib/**/*.ex`, excluding generated dir) and extracts all calls to configured library modules.

```elixir
# Detects: Numpy.array/1, Numpy.mean/1, Numpy.std/1
# From aliases, imports, and direct calls
```

### Phase 2: Compare

Compare detected symbols against the manifest. Only new symbols need generation.

```
Detected: {Numpy, :array, 1}, {Numpy, :mean, 1}, {Numpy, :std, 1}
Manifest: {Numpy, :array, 1}
─────────────────────────────────────────────────────────────────
To Generate: {Numpy, :mean, 1}, {Numpy, :std, 1}
```

### Phase 3: Introspect

Query Python (via UV) for function signatures and docstrings.

```python
# Introspection script output:
{
  "name": "mean",
  "parameters": [
    {"name": "a", "kind": "POSITIONAL_OR_KEYWORD"},
    {"name": "axis", "kind": "KEYWORD_ONLY", "default": "None"}
  ],
  "docstring": "Compute the arithmetic mean along the specified axis..."
}
```

### Phase 4: Generate

Produce Elixir source file with all functions for the library, sorted alphabetically.

```elixir
# lib/snakebridge_generated/numpy.ex
defmodule Numpy do
  @moduledoc "SnakeBridge bindings for numpy."
  
  @doc "Return a new array of given shape and type, filled with `fill_value`."
  def array(object), do: SnakeBridge.Runtime.call(__MODULE__, :array, [object])
  
  @doc "Compute the arithmetic mean along the specified axis."
  def mean(a), do: SnakeBridge.Runtime.call(__MODULE__, :mean, [a])
  
  @doc "Compute the standard deviation along the specified axis."
  def std(a), do: SnakeBridge.Runtime.call(__MODULE__, :std, [a])
end
```

### Phase 5: Update Manifest & Lock

Record what was generated and capture environment identity.

## Strict Mode

For CI environments, strict mode ensures no generation occurs unexpectedly:

```elixir
# config/prod.exs
config :snakebridge, strict: true
```

With `strict: true`:
- Build **fails** if any symbol would need generation
- Ensures committed source matches detected usage
- No Python required at build time

## Runtime Flow

At runtime, generated modules delegate to Snakepit:

```
Numpy.mean(arr)
    │
    ▼
SnakeBridge.Runtime.call(Numpy, :mean, [arr])
    │
    ▼
Snakepit.execute("snakebridge.call", %{library: "numpy", function: "mean", args: [arr], kwargs: %{}})
    │
    ▼
gRPC to Python worker → numpy.mean(a) → result
    │
    ▼
{:ok, 3.14159}
```

Snakepit handles:
- Worker pooling and lifecycle
- Session affinity (if using sessions)
- Streaming for large results
- Telemetry and observability

## Snakepit Integration Contract

SnakeBridge uses Snakepit as a runtime substrate via a dedicated Python adapter.

**Required Snakepit config:**

```elixir
config :snakepit,
  pooling_enabled: true,
  adapter_module: Snakepit.Adapters.GRPCPython,
  adapter_args: ["--adapter", "snakebridge_adapter"]
```

**Runtime calls:**

```
SnakeBridge.Runtime.call(Numpy, :mean, [arr], [axis: 0])
  -> Snakepit.execute("snakebridge.call", %{
       library: "numpy",
       function: "mean",
       args: [arr],
       kwargs: %{axis: 0}
     })
```

**Streaming calls:**

```
SnakeBridge.Runtime.stream(Numpy, :predict, [input], [], fn chunk -> ... end)
  -> Snakepit.execute_stream("snakebridge.stream", payload, callback)
```

This contract keeps SnakeBridge focused on codegen while Snakepit handles pools, sessions, and streaming.

## Key Design Decisions

See [10-engineering-decisions.md](10-engineering-decisions.md) for full rationale.

| Decision | Choice | Why |
|----------|--------|-----|
| Generation timing | Pre-pass (before Elixir compile) | Tooling compatibility |
| Cache format | Source `.ex` files | Portable across OTP versions |
| Git status | Committed | Deterministic CI, faster builds |
| Pruning | Explicit only | Determinism over automation |
| Doc source | Python authoritative (metadata fallback) | Accuracy + offline option |
| Dynamic calls | Ledger + promote | Controlled, reproducible |

## Configuration

```elixir
# mix.exs
{:snakebridge, "~> 3.0",
 libraries: [
   numpy: "~> 1.26",
   pandas: "~> 2.0",
   sympy: "~> 1.12"
 ]}
```

See [01-configuration.md](01-configuration.md) for full options.

## Related Documents

| Document | Description |
|----------|-------------|
| [01-configuration.md](01-configuration.md) | Full configuration reference |
| [02-scanner.md](02-scanner.md) | AST scanning implementation |
| [03-introspector.md](03-introspector.md) | Python introspection |
| [04-generator.md](04-generator.md) | Code generation |
| [05-cache-manifest.md](05-cache-manifest.md) | Caching and determinism |
| [06-documentation.md](06-documentation.md) | On-demand docs |
| [07-pruning.md](07-pruning.md) | Explicit cleanup |
| [08-developer-experience.md](08-developer-experience.md) | IDE, IEx, tooling |
| [09-agentic-workflows.md](09-agentic-workflows.md) | AI/automation APIs |
| [10-engineering-decisions.md](10-engineering-decisions.md) | Design rationale |
| [11-implementation-roadmap.md](11-implementation-roadmap.md) | Build plan |
| [12-migration-guide.md](12-migration-guide.md) | v0.4 → v3 upgrade |
| [13-typespecs.md](13-typespecs.md) | Typespecs and type mapping |
| [14-runtime-integration.md](14-runtime-integration.md) | Snakepit runtime contract |
| [15-error-handling.md](15-error-handling.md) | Error categories and surfaces |
| [16-mix-tasks.md](16-mix-tasks.md) | CLI task reference |
