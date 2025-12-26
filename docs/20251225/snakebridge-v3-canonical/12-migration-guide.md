# Migration Guide: v0.4 to v3

## Overview

SnakeBridge v3 is a fundamental architectural change from v0.4. This guide helps you migrate existing projects.

## Key Differences

| Aspect | v0.4 (Eager) | v3 (Lazy) |
|--------|--------------|-----------|
| **Configuration** | `config :snakebridge, adapters: [...]` | `{:snakebridge, libraries: [...]}` in mix.exs |
| **Generation** | Full library at compile time | Only used functions |
| **Cache** | Ephemeral, regenerated each build | Persistent, committed to git |
| **Pruning** | Implicit (regenerate all) | Explicit developer action |
| **Output** | `lib/snakebridge_generated/<lib>/<lib>.ex` | `lib/snakebridge_generated/<lib>.ex` |

## Migration Steps

### Step 1: Update Dependency

**Before (v0.4):**

```elixir
# mix.exs
defp deps do
  [
    {:snakebridge, "~> 0.4"},
    {:snakepit, "~> 0.7"}
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
       numpy: "~> 1.26",
       pandas: "~> 2.0"
     ]}
    # snakepit is now a transitive dependency
  ]
end

def project do
  [
    compilers: [:snakebridge] ++ Mix.compilers(),
    # ...
  ]
end
```

### Step 2: Move Configuration

**Before (v0.4):**

```elixir
# config/config.exs
config :snakebridge,
  adapters: [:json, :math, :sympy]
```

**After (v3):**

```elixir
# mix.exs - libraries in dependency
{:snakebridge, "~> 3.0",
 libraries: [
   json: :stdlib,
   math: :stdlib,
   sympy: "~> 1.12"
 ]}

# config/config.exs - only runtime options
config :snakebridge,
  verbose: false,
  strict: false
```

### Step 3: Clean Old Generated Code

```bash
# Remove old generated structure
rm -rf lib/snakebridge_generated/

# Remove old gitignore (v3 commits generated code)
# Check .gitignore for snakebridge entries
```

### Step 4: First v3 Compile

```bash
$ mix deps.get
$ mix compile

SnakeBridge: Scanning project...
SnakeBridge: Detected 5 library calls
SnakeBridge: Generating numpy.ex (3 functions)
SnakeBridge: Generating pandas.ex (2 functions)
Compiled 17 files (0.3s)
```

### Step 5: Commit Generated Code

```bash
$ git add lib/snakebridge_generated/
$ git add .snakebridge/manifest.json
$ git add snakebridge.lock
$ git commit -m "Migrate to SnakeBridge v3"
```

## Code Changes

### Module Names

Module names are unchanged by default:

```elixir
# Both v0.4 and v3
Numpy.array([1, 2, 3])
Json.dumps(%{})
```

### Return Values

v3 always returns tagged tuples:

```elixir
# v0.4 might return raw values or tuples
result = Sympy.solve(expr, x)

# v3 always returns {:ok, _} or {:error, _}
{:ok, result} = Sympy.solve(expr, x)
```

Update your code to pattern match:

```elixir
# Before
result = Numpy.mean(arr)
process(result)

# After
case Numpy.mean(arr) do
  {:ok, result} -> process(result)
  {:error, reason} -> handle_error(reason)
end

# Or with bang version (future)
result = Numpy.mean!(arr)
```

### Discovery Functions

Discovery API is similar but slightly changed:

```elixir
# v0.4
Json.__functions__()
# => [{:dump, 12, Json, "..."}, ...]

# v3 (same format)
Json.__functions__()
# => [{:dump, 12, Json, "..."}, ...]

# v3 adds
Json.doc(:dump)      # Get documentation
Json.__search__("encode")  # Search functions
```

## Configuration Mapping

| v0.4 Config | v3 Equivalent |
|-------------|---------------|
| `adapters: [:numpy]` | `libraries: [numpy: "~> 1.26"]` |
| `adapters: [{:numpy, functions: [...]}]` | `libraries: [numpy: [version: "~> 1.26", include: [...]]]` |
| Snakepit config | Unchanged (still in config.exs) |

## CI/CD Changes

### GitHub Actions

```yaml
# v0.4 - regenerates every build
- run: mix compile

# v3 - uses committed code, strict mode
- run: mix compile
  env:
    SNAKEBRIDGE_STRICT: "true"
```

### Verify Generated Code

```yaml
- name: Verify no drift
  run: |
    mix snakebridge.verify
    git diff --exit-code lib/snakebridge_generated/
```

## Common Issues

### Issue: "Module Numpy not available"

**Cause**: Library not in mix.exs

**Solution:**
```elixir
{:snakebridge, "~> 3.0",
 libraries: [numpy: "~> 1.26"]}
```

### Issue: Compile fails with strict mode

**Cause**: New function usage not in manifest

**Solution:**
```bash
# In development
$ mix compile  # Generates new functions
$ git add lib/snakebridge_generated/
$ git commit -m "Add new library functions"
```

### Issue: Old generated files lingering

**Cause**: v3 uses different file structure

**Solution:**
```bash
$ rm -rf lib/snakebridge_generated/
$ mix compile  # Fresh generation
```

### Issue: Different function count

**Cause**: v3 only generates used functions

**This is expected**. v3 generates ~10 functions instead of ~800 for numpy because it only generates what you use.

## Rollback Plan

If you need to rollback to v0.4:

```elixir
# mix.exs
{:snakebridge, "~> 0.4"}
```

```elixir
# config/config.exs
config :snakebridge,
  adapters: [:json, :math, :sympy]
```

```bash
$ rm -rf lib/snakebridge_generated/
$ rm -rf .snakebridge/
$ rm snakebridge.lock
$ mix deps.get
$ mix compile
```

## Checklist

- [ ] Update `:snakebridge` dependency in mix.exs
- [ ] Add `libraries:` option with Python libraries
- [ ] Add `:snakebridge` to compilers list
- [ ] Remove `config :snakebridge, adapters: [...]`
- [ ] Delete old `lib/snakebridge_generated/` directory
- [ ] Run `mix deps.get`
- [ ] Run `mix compile`
- [ ] Update code to handle `{:ok, _} | {:error, _}` returns
- [ ] Run tests
- [ ] Commit generated code to git
- [ ] Update CI to use strict mode

## Getting Help

- **Docs**: https://hexdocs.pm/snakebridge
- **Issues**: https://github.com/nshkrdotcom/snakebridge/issues

When reporting issues, include:
1. Your v0.4 configuration
2. Error messages
3. `mix snakebridge.doctor` output
