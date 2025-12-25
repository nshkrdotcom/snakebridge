# Migration Guide: v2 to v3

## Overview

SnakeBridge v3 represents a fundamental shift in architecture. This guide helps you migrate existing v2 projects to v3.

## Key Differences

| Aspect | v2 (Eager) | v3 (Lazy) |
|--------|------------|-----------|
| **Configuration** | `config/config.exs` adapters list | `mix.exs` libraries in dep |
| **Generation** | Full API at compile time | On-demand during compilation |
| **Cache** | Ephemeral, regenerated each build | Persistent, accumulates |
| **Pruning** | Implicit (always regenerate) | Explicit developer action |
| **Documentation** | Pre-built artifacts | Query on demand |
| **Python setup** | Manual pip/venv | Automatic via UV |

## Migration Steps

### Step 1: Update Dependency

**Before (v2):**

```elixir
# mix.exs
defp deps do
  [
    {:snakebridge, "~> 0.4"},
    {:snakepit, "~> 0.7"}  # If using pooling
  ]
end
```

**After (v3):**

```elixir
# mix.exs
defp deps do
  [
    {:snakebridge, "~> 3.0",
     libraries: [
       # Your Python libraries here
     ]}
  ]
end
```

### Step 2: Move Library Configuration

**Before (v2):**

```elixir
# config/config.exs
config :snakebridge,
  adapters: [:json, :math, :sympy]

# Separate Python requirements
# requirements.txt or pyproject.toml
# sympy==1.12
```

**After (v3):**

```elixir
# mix.exs - everything in one place
{:snakebridge, "~> 3.0",
 libraries: [
   json: :stdlib,    # stdlib doesn't need version
   math: :stdlib,
   sympy: "~> 1.12"  # version specified here
 ]}
```

### Step 3: Remove Old Configuration

Delete or update these files:

```bash
# Remove old adapter configs
rm config/snakebridge.exs  # If exists

# Remove Python dependency files (UV handles this now)
rm requirements.txt
rm pyproject.toml  # Unless you have other Python needs
```

**Before (v2):**

```elixir
# config/config.exs
import Config

config :snakebridge,
  adapters: [:json, :math, :sympy],
  pooling_enabled: true,
  pool_size: 5

config :snakepit,
  python_path: "/usr/bin/python3",
  adapter_module: SnakeBridge.Adapters.SnakepitAdapter
```

**After (v3):**

```elixir
# config/config.exs
import Config

config :snakebridge,
  verbose: false  # Optional, v3 has sensible defaults
```

### Step 4: Update Module References

If you used custom module names in v2, specify them explicitly:

**Before (v2):**

```elixir
# Usage
alias SnakeBridge.Adapters.Numpy
Numpy.array([1, 2, 3])
```

**After (v3):**

```elixir
# Usage - direct module names
Numpy.array([1, 2, 3])

# Or with custom names in mix.exs:
# numpy: [version: "~> 1.26", module_name: Np]
Np.array([1, 2, 3])
```

### Step 5: Update Function Calls

v3 uses a consistent return format:

**Before (v2):**

```elixir
# v2 might return raw values or tuples depending on adapter
result = Sympy.solve(expr, x)
# Could be: [1, 2] or {:ok, [1, 2]} or {:error, ...}
```

**After (v3):**

```elixir
# v3 always returns tagged tuples
{:ok, result} = Sympy.solve(expr, x)
# Always {:ok, value} or {:error, reason}

# Pattern matching recommended
case Numpy.array([1, 2, 3]) do
  {:ok, arr} -> process(arr)
  {:error, reason} -> handle_error(reason)
end
```

### Step 6: Remove Snakepit Dependencies

v3 doesn't require Snakepit for basic usage:

**Before (v2):**

```elixir
# Had to configure Snakepit separately
config :snakepit,
  python_path: System.get_env("PYTHON_PATH") || "python3",
  pool_size: 4

# And handle adapter setup
defmodule MyApp.Application do
  def start(_type, _args) do
    children = [
      {Snakepit.Pool, name: :python_pool, size: 4}
    ]
    # ...
  end
end
```

**After (v3):**

```elixir
# No pool configuration needed
# UV handles Python environment automatically
# Just use the libraries directly
```

### Step 7: Handle First Compilation

After migrating, your first compilation will generate bindings:

```bash
$ mix compile
SnakeBridge: Initializing cache at _build/snakebridge
SnakeBridge: Generated Sympy.solve/2 (145ms)
SnakeBridge: Generated Sympy.Symbol/1 (32ms)
SnakeBridge: Generated Json.dumps/1 (28ms)
Compiled 15 files (0.8s)
```

Subsequent compilations use the cache:

```bash
$ mix compile
Compiled 0 files (0.05s)
```

## Migration Automation

### Automatic Migration Tool

v3 includes a migration helper:

```bash
$ mix snakebridge.migrate

SnakeBridge v2 to v3 Migration
==============================

Detected v2 configuration:
  config/config.exs: adapters: [:json, :math, :sympy]

Proposed changes:

1. Update mix.exs:
   {:snakebridge, "~> 3.0",
    libraries: [
      json: :stdlib,
      math: :stdlib,
      sympy: "*"  # TODO: Specify version
    ]}

2. Remove from config/config.exs:
   - config :snakebridge, adapters: [...]

3. Archive v2 cache (if any):
   _build/snakebridge_v2_archived/

Apply changes? [y/N]:
```

### Manual Checklist

- [ ] Update `:snakebridge` dependency in mix.exs
- [ ] Add `libraries:` option with your Python libraries
- [ ] Remove `config :snakebridge, adapters: [...]` from config
- [ ] Remove Snakepit configuration (if not using pooling)
- [ ] Update function calls to expect `{:ok, _}` or `{:error, _}`
- [ ] Run `mix deps.get`
- [ ] Run `mix compile` (first compile generates bindings)
- [ ] Run tests to verify functionality
- [ ] Commit updated mix.exs and lock file

## Common Issues

### Issue: "Module Numpy is not available"

**Cause:** Library not configured in mix.exs

**Solution:**
```elixir
# Add to mix.exs
{:snakebridge, "~> 3.0",
 libraries: [
   numpy: "~> 1.26"  # Add missing library
 ]}
```

### Issue: "UV command not found"

**Cause:** UV not installed

**Solution:**
```bash
# Install UV
curl -LsSf https://astral.sh/uv/install.sh | sh

# Or via pip
pip install uv

# Or via Homebrew
brew install uv
```

### Issue: Version mismatch warnings

**Cause:** v2 used different Python library versions

**Solution:**
```elixir
# Specify exact version to match v2 behavior
libraries: [
  sympy: "== 1.12.0"  # Exact match
]
```

### Issue: Slow first compilation

**Cause:** All bindings being generated fresh

**Solution:** This is expected for first compile. Subsequent compiles use cache.

```bash
# Pre-warm cache for all used functions
$ mix snakebridge.generate --from lib/
```

### Issue: "Function not found in library"

**Cause:** Python library version doesn't have that function

**Solution:**
```elixir
# Check which version introduced the function
# and update version constraint
libraries: [
  numpy: "~> 2.0"  # Use newer version
]
```

## Rollback Plan

If you need to rollback to v2:

```elixir
# mix.exs - Revert dependency
{:snakebridge, "~> 0.4"}

# Restore config/config.exs
config :snakebridge,
  adapters: [:json, :math, :sympy]
```

```bash
# Clean v3 cache
rm -rf _build/snakebridge

# Reinstall deps
mix deps.get
mix compile
```

## Performance Comparison

### Compilation Time

| Scenario | v2 | v3 |
|----------|----|----|
| First compile (10 functions) | 5-10s | 2-3s |
| First compile (100 functions) | 30-60s | 5-10s |
| First compile (1000 functions) | 5-10min | 15-30s |
| Incremental (no changes) | 1-2s | <0.1s |
| Incremental (1 new function) | 5-10s | 0.1-0.2s |

### Runtime Performance

| Operation | v2 | v3 |
|-----------|----|----|
| Python call overhead | ~5ms | ~5ms |
| With pooling | ~2ms | ~2ms (future) |

Runtime performance is similar. The main improvement is in compilation.

## Feature Comparison

### v2 Features → v3 Equivalents

| v2 Feature | v3 Equivalent |
|------------|---------------|
| `adapters: [:numpy]` | `libraries: [numpy: "~> 1.26"]` |
| `pooling_enabled: true` | Future: `pool: [size: 4]` |
| Pre-built docs | `Numpy.doc(:array)` |
| Snakepit adapter | Built-in UV runtime |
| requirements.txt | Version in mix.exs |

### New in v3

- Lazy compilation (only used functions)
- Persistent cache
- Explicit pruning
- On-demand documentation
- Automatic UV integration
- Cache analysis tools
- Version-locked dependencies

## Getting Help

- **Documentation**: https://hexdocs.pm/snakebridge
- **Issues**: https://github.com/snakebridge/snakebridge/issues
- **Discussions**: https://github.com/snakebridge/snakebridge/discussions

When reporting migration issues, include:
1. Your v2 configuration
2. Error messages
3. `mix snakebridge.analyze` output (if v3 partially works)
