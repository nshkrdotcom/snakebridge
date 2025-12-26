# Cache and Manifest

## Philosophy

The cache follows an **append-only accumulation model**. Generated source only grows; deletions are explicit developer actions. This ensures deterministic, reproducible builds.

**Key Decision**: We cache **source files** (`.ex`), not BEAM bytecode. Source is portable across OTP/Elixir versions.

## File Structure

```
my_app/
├── lib/snakebridge_generated/       # Generated source (committed to git)
│   ├── numpy.ex                     # All Numpy functions
│   ├── pandas.ex                    # All Pandas functions
│   └── sympy.ex                     # All Sympy functions
├── .snakebridge/
│   ├── manifest.json                # Symbol tracking (committed)
│   ├── scan_cache.json              # File hash cache (local)
│   └── ledger.json                  # Dynamic call log (dev only, NOT committed)
├── snakebridge.lock                 # Environment lock (committed)
└── _build/                          # Compiled BEAM (not committed)
```

## Manifest

The manifest tracks all generated symbols. It is stable and deterministic:

- No timestamps (avoids diff churn)
- Sorted keys
- Rebuildable from generated source if needed

```json
{
  "version": "3.0.0",
  "symbols": {
    "Numpy.array/1": {
      "python_name": "array",
      "source_file": "lib/snakebridge_generated/numpy.ex",
      "checksum": "sha256:abc123..."
    },
    "Numpy.mean/1": {
      "python_name": "mean",
      "source_file": "lib/snakebridge_generated/numpy.ex",
      "checksum": "sha256:def456..."
    }
  }
}
```

### Manifest Operations

```elixir
defmodule SnakeBridge.Manifest do
  @manifest_path ".snakebridge/manifest.json"

  def load do
    case File.read(@manifest_path) do
      {:ok, content} -> Jason.decode!(content)
      {:error, :enoent} -> %{"version" => "3.0.0", "symbols" => %{}}
    end
  end

  def save(manifest) do
    content = manifest
    |> sort_keys()
    |> Jason.encode!(pretty: true)
    
    File.mkdir_p!(Path.dirname(@manifest_path))
    File.write!(@manifest_path, content)
  end

  def missing(manifest, detected) do
    existing = MapSet.new(Map.keys(manifest["symbols"]))
    detected_keys =
      detected
      |> Enum.map(fn {m, f, a} -> "#{m}.#{f}/#{a}" end)
      |> MapSet.new()
    
    MapSet.difference(detected_keys, existing)
    |> MapSet.to_list()
    |> Enum.map(&parse_symbol_key/1)
  end

  defp sort_keys(manifest) do
    update_in(manifest, ["symbols"], fn symbols ->
      symbols |> Enum.sort() |> Map.new()
    end)
  end
end
```

## Lock File

The lock file captures complete environment identity. SnakeBridge records
Python/runtime identity as reported by Snakepit Prime (managed or system):

```json
{
  "version": "3.0.0",
  "environment": {
    "snakebridge_version": "3.0.0",
    "generator_hash": "sha256:...",
    "python_version": "3.11.5",
    "python_platform": "linux-x86_64",
    "python_runtime_hash": "sha256:...",
    "elixir_version": "1.16.0",
    "otp_version": "26.1"
  },
  "libraries": {
    "numpy": {
      "requested": "~> 1.26",
      "resolved": "1.26.4",
      "hash": "sha256:..."
    },
    "pandas": {
      "requested": "~> 2.0", 
      "resolved": "2.1.4",
      "hash": "sha256:..."
    }
  },
  "metadata": {
    "source": "python",
    "hash": "sha256:..."
  },
  "hardware": {
    "cuda": "12.1",
    "cudnn": "8.9.0",
    "accelerators": ["cuda"]
  }
}
```

### Invalidation

When environment changes, affected bindings are regenerated:

| Change | Effect |
|--------|--------|
| SnakeBridge version | Regenerate all |
| Python version | Regenerate all |
| Library version | Regenerate that library |
| Platform change | Regenerate all |
| New symbol in code | Generate that symbol |
| Symbol removed from code | Keep (prune explicitly) |

## Ledger

The ledger captures dynamic calls that AST scanning can't detect:

```json
{
  "dynamic_calls": [
    {
      "module": "Numpy",
      "function": "custom_op",
      "arity": 3,
      "count": 5,
      "first_seen": "2025-12-25T10:00:00Z",
      "last_seen": "2025-12-25T14:30:00Z"
    }
  ]
}
```

### Recording Dynamic Calls

```elixir
# In dev, dynamic calls are recorded by the runtime path.
# Use Snakepit.dynamic_call/4 (or SnakeBridge.DynamicCall wrapper) so the
# ledger is updated deterministically.
Snakepit.dynamic_call(:numpy, :custom_op, [a, b, c])
```

### Promoting Ledger to Manifest

```bash
$ mix snakebridge.ledger
Dynamic calls detected (not in manifest):
  Numpy.custom_op/3 - called 5 times
  Pandas.query/2 - called 2 times

$ mix snakebridge.promote
Promoting 2 symbols to manifest...
Regenerating numpy.ex
Regenerating pandas.ex
Done. Commit the changes.
```

The ledger is **NOT committed** to git—it's local development data. Only after explicit promotion do symbols become permanent.

## Why Source Caching?

### BEAM Bytecode Problems

```
OTP 26 machine ──compile──► numpy.beam ──load──► OTP 27 machine
                                           ╳
                                    May fail or behave
                                    unexpectedly
```

BEAM files have version constraints:
- OTP version compatibility
- Elixir compiler changes
- Debug info settings
- Compilation flags

### Source Solution

```
Source ──commit──► Git ──checkout──► Any machine ──compile──► Local BEAM
  ✓                                       ✓                        ✓
Portable                            Same source               Works correctly
```

Source is universally portable. Each machine compiles to its own BEAM.

## Git Integration

### What to Commit

```gitignore
# .gitignore

# DO commit these:
#   lib/snakebridge_generated/*.ex    (generated source)
#   .snakebridge/manifest.json        (symbol tracking)
#   snakebridge.lock                  (environment lock)

# Do NOT commit:
.snakebridge/ledger.json              # Development-only dynamic call log
```

### Git Attributes

```gitattributes
# Mark as generated for cleaner PRs
lib/snakebridge_generated/* linguist-generated=true

# Merge-friendly (sorted keys)
.snakebridge/manifest.json merge=union
snakebridge.lock merge=ours
```

If `snakebridge.lock` conflicts, regenerate it:

```bash
mix snakebridge.lock --rebuild
```

## Merge Conflict Prevention

### Sorted Keys

All JSON files use sorted keys:

```json
{
  "symbols": {
    "Numpy.array/1": {...},
    "Numpy.mean/1": {...},   // Always after array
    "Numpy.std/1": {...}     // Always after mean
  }
}
```

### One-Line-Per-Entry

```json
{
  "symbols": {
    "Numpy.array/1": {"python_name": "array"},
    "Numpy.mean/1": {"python_name": "mean"}
  }
}
```

When two developers add different functions:

```
Dev A adds: "Numpy.sum/1": {...}
Dev B adds: "Numpy.dot/2": {...}

Merge result:
  "Numpy.array/1": {...},
  "Numpy.dot/2": {...},    ← B's addition
  "Numpy.mean/1": {...},
  "Numpy.std/1": {...},
  "Numpy.sum/1": {...}     ← A's addition
```

Clean merge in most cases.

## Verification

```bash
$ mix snakebridge.verify
Verifying cache integrity...
  ✓ manifest.json valid
  ✓ snakebridge.lock matches environment
  ✓ numpy.ex matches manifest (3 symbols)
  ✓ pandas.ex matches manifest (2 symbols)
All OK.
```

### Repair

```bash
$ mix snakebridge.verify
Verifying cache integrity...
  ✗ numpy.ex missing: reshape/2 (in manifest but not in source)
  ✓ pandas.ex OK

$ mix snakebridge.repair
Regenerating numpy.ex (adding reshape/2)...
Done.
```

## CI Workflow

### With Committed Source

```yaml
# .github/workflows/ci.yml
jobs:
  build:
    steps:
      - uses: actions/checkout@v3
      # No Python setup needed for compile!
      # Generated source is already in repo
      
      - name: Install Elixir
        uses: erlef/setup-beam@v1
        
      - name: Build
        run: mix compile --warnings-as-errors
        env:
          SNAKEBRIDGE_STRICT: "true"  # Fail if regeneration needed
```

### Verify No Drift

```yaml
      - name: Verify generated code is up-to-date
        run: |
          mix snakebridge.verify
          git diff --exit-code lib/snakebridge_generated/
```

## Performance

| Operation | Time |
|-----------|------|
| Load manifest | <1ms |
| Check missing symbols | <1ms |
| Write manifest | <10ms |
| Full verification | <100ms |

The manifest is designed for fast lookups—hash table semantics.
