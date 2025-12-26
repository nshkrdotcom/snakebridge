# Implementation Roadmap

## Overview

This document outlines the technical implementation plan for SnakeBridge v3. The architecture uses a **pre-compilation generation pass** that produces real `.ex` source files.

## Architecture Summary

```
mix compile
    │
    ├── 1. SnakeBridge Compiler (runs first)
    │       ├── Scan project AST
    │       ├── Compare to manifest
    │       ├── Generate missing .ex files
    │       └── Update manifest + lock
    │
    ├── 2. Elixir Compiler (normal)
    │       └── Compiles all .ex including generated
    │
    └── 3. App ready
```

## Project Structure

```
lib/
├── snakebridge.ex                    # Public API
├── snakebridge/
│   ├── config.ex                     # Configuration from mix.exs
│   ├── scanner.ex                    # AST scanning
│   ├── introspector.ex               # Python introspection
│   ├── generator.ex                  # Source generation
│   ├── manifest.ex                   # Manifest management
│   ├── lock.ex                       # Lock file management
│   ├── ledger.ex                     # Runtime usage ledger
│   ├── types.ex                      # Typespec mapping + PyRef struct
│   ├── docs.ex                       # Documentation system
│   └── runtime.ex                    # Payload helper (delegates to Snakepit)
├── mix/
│   └── tasks/
│       ├── compile/
│       │   └── snakebridge.ex        # Compiler task
│       ├── snakebridge.generate.ex
│       ├── snakebridge.prune.ex
│       ├── snakebridge.verify.ex
│       ├── snakebridge.analyze.ex
│       ├── snakebridge.ledger.ex
│       ├── snakebridge.promote.ex
│       └── snakebridge.doctor.ex
```

## Phase 1: Configuration

**Goal**: Parse library configuration from mix.exs dependency options.

### 1.1 Config Module

```elixir
defmodule SnakeBridge.Config do
  defstruct [:libraries, :generated_dir, :metadata_dir, :strict, :verbose]

  def load do
    deps = Mix.Project.config()[:deps] || []
    
    case find_snakebridge_dep(deps) do
      {_, opts} when is_list(opts) -> parse(opts)
      _ -> %__MODULE__{libraries: []}
    end
  end

  def parse(opts) do
    %__MODULE__{
      libraries: parse_libraries(opts[:libraries] || []),
      generated_dir: opts[:generated_dir] || "lib/snakebridge_generated",
      metadata_dir: opts[:metadata_dir] || ".snakebridge",
      strict: Application.get_env(:snakebridge, :strict, false),
      verbose: Application.get_env(:snakebridge, :verbose, false)
    }
  end
end
```

### 1.2 Tests

- Parse simple version string
- Parse stdlib modules
- Parse custom module names
- Parse include/exclude lists

---

## Phase 2: AST Scanner

**Goal**: Detect library calls in project source.

### 2.1 Scanner Module

```elixir
defmodule SnakeBridge.Scanner do
  def scan_project(config) do
    library_modules = config.libraries |> Enum.map(& &1.module_name)
    
    source_files(config)
    |> Task.async_stream(&scan_file(&1, library_modules), ordered: false)
    |> Enum.flat_map(fn {:ok, calls} -> calls end)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
```

### 2.2 Key Features

- Detect direct calls (`Numpy.array`)
- Resolve aliases (`alias Numpy, as: Np`)
- Handle imports (`import Numpy, only: [array: 1]`)
- Exclude generated directory

---

## Phase 3: Introspector

**Goal**: Query Python for function signatures and docs.

### 3.1 Introspector Module

```elixir
defmodule SnakeBridge.Introspector do
  def introspect(library, functions) do
    script = introspection_script()
    
    case run_python(library, script, functions) do
      {:ok, output} -> parse_output(output)
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_python(library, script, functions) do
    if library.version == :stdlib do
      System.cmd("python3", ["-c", script, ...])
    else
      System.cmd("uv", ["run", "--with", version_spec, "python", "-c", script, ...])
    end
  end
end
```

### 3.2 Output Format

```json
{
  "name": "array",
  "parameters": [...],
  "docstring": "...",
  "callable": true
}
```

---

## Phase 4: Generator

**Goal**: Produce deterministic `.ex` source files.

### 4.1 Generator Module

```elixir
defmodule SnakeBridge.Generator do
  def generate(to_generate, introspection, config) do
    File.mkdir_p!(config.generated_dir)
    
    to_generate
    |> group_by_library(config)
    |> Enum.each(&generate_library(&1, introspection, config))
  end
end
```

### 4.2 Key Features

- One file per library
- Functions sorted alphabetically
- Atomic writes (temp file + rename)
- No timestamps in output

---

## Phase 5: Manifest & Lock

**Goal**: Track generated symbols and environment.

### 5.1 Manifest

```elixir
defmodule SnakeBridge.Manifest do
  @path ".snakebridge/manifest.json"

  def load, do: ...
  def save(manifest), do: ... # sorted keys, no timestamps
  def missing(manifest, detected), do: ...
  def add_symbols(manifest, symbols), do: ...
end
```

### 5.2 Lock

```elixir
defmodule SnakeBridge.Lock do
  @path "snakebridge.lock"

  def load, do: ...
  def save(lock), do: ...
  def validate(lock, current_env), do: ...
end
```

---

## Phase 6: Compiler Task

**Goal**: Integrate with Mix compilation.

### 6.1 Compiler

```elixir
defmodule Mix.Tasks.Compile.Snakebridge do
  use Mix.Task.Compiler

  @impl true
  def run(_args) do
    config = SnakeBridge.Config.load()
    
    if config.libraries == [] do
      {:ok, []}
    else
      SnakeBridge.Lock.acquire!()    # file lock around generation
      detected = SnakeBridge.Scanner.scan_project(config)
      manifest = SnakeBridge.Manifest.load()
      to_generate = SnakeBridge.Manifest.missing(manifest, detected)
      
      if to_generate != [] and config.strict do
        {:error, [diagnostic(:strict_mode_violation, to_generate)]}
      else
        if to_generate != [] do
          {:ok, introspection} = SnakeBridge.Introspector.introspect_batch(to_generate)
          SnakeBridge.Generator.generate(to_generate, introspection, config)
        end
        
        SnakeBridge.Manifest.update(manifest, detected)
        SnakeBridge.Lock.update(config)
        SnakeBridge.Lock.release!()
        {:ok, []}
      end
    end
  end
end
```

---

## Phase 7: Mix Tasks

**Goal**: Developer-facing CLI tools.

| Task | Purpose |
|------|---------|
| `mix snakebridge.generate` | Manual generation |
| `mix snakebridge.scan` | Scan and list detected symbols |
| `mix snakebridge.prune` | Remove unused symbols |
| `mix snakebridge.verify` | Verify cache integrity |
| `mix snakebridge.repair` | Repair missing symbols |
| `mix snakebridge.analyze` | Show cache analysis |
| `mix snakebridge.ledger` | Show dynamic calls |
| `mix snakebridge.promote` | Promote ledger to manifest |
| `mix snakebridge.doctor` | Check environment |
| `mix snakebridge.lock` | Rebuild lockfile |

---

## Phase 8: Docs + Payload Helper

**Goal**: Provide documentation and a thin payload helper for Snakepit.

SnakeBridge does not implement runtime behavior. It provides a small helper
that constructs payloads and delegates to Snakepit Prime. Ledger recording
can be enabled in dev, but execution is always in Snakepit.

### 8.1 Docs

```elixir
defmodule SnakeBridge.Docs do
  def get(module, function) do
    case cache_lookup(module, function) do
      {:ok, doc} -> doc
      :miss -> fetch_and_cache(module, function)
    end
  end
end
```

---

## Phase 9: Runtime Alignment (Snakepit)

**Goal**: Ensure generated payloads and types align with Snakepit Prime runtime.

- Payload fields: `kwargs`, `call_type`, `idempotent`
- Handle types: `Snakepit.PyRef`, `Snakepit.ZeroCopyRef`
- Error types: `Snakepit.Error.*`

See `14-runtime-integration.md` and `17-ml-pillars.md`.

---

## Milestones

| Phase | Deliverable | Success Criteria |
|-------|-------------|------------------|
| 1 | Config | Parses mix.exs correctly |
| 2 | Scanner | Detects all library calls |
| 3 | Introspector | Gets Python signatures |
| 4 | Generator | Produces valid `.ex` files |
| 5 | Manifest/Lock | Tracks symbols, environment |
| 6 | Compiler | Integrates with `mix compile` |
| 7 | Mix Tasks | All CLI tools work |
| 8 | Runtime/Docs | Calls work, docs queryable |
| 9 | ML Pillars | Zero-copy + crash barrier + hermetic runtime |
| **v3.0.0** | **Release** | All tests pass |

---

## MVP Definition

**Required for v3.0.0:**

1. ✅ Configuration parsing from mix.exs
2. ✅ AST scanning for library calls
3. ✅ Python introspection via UV
4. ✅ Source generation to `lib/snakebridge_generated/`
5. ✅ Manifest tracking
6. ✅ Lock file for environment
7. ✅ Runtime via Snakepit
8. ✅ `mix compile` integration
9. ✅ `mix snakebridge.generate`
10. ✅ `mix snakebridge.prune`
11. ✅ Strict mode for CI

**Deferred to v3.1+:**

- Shared cache server
- Community registry packages
- Advanced type mapping
- IDE plugin protocols
- GPU/CUDA optimizations

---

## Dependencies

```elixir
defp deps do
  [
    {:snakepit, "~> 0.7.3"},   # Runtime substrate
    {:jason, "~> 1.4"}         # JSON parsing
  ]
end
```

No other dependencies. UV handles Python packages.
