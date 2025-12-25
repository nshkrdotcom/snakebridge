# Accumulator Cache

## Philosophy

The cache follows an **append-only accumulation model** during development. Like a git repository, it only grows—deletions are explicit, intentional operations that require developer consent.

## Why Accumulation?

### The Problem with Auto-Cleanup

Imagine this scenario:

```
Day 1: Developer uses Numpy.fft
Day 2: Developer refactors, fft usage moves to a different module
Day 3: Auto-prune removes Numpy.fft (not detected in current compile)
Day 4: CI fails - the other module needed fft
```

Auto-cleanup creates **non-deterministic builds**. The same code can fail or succeed depending on what the cache saw previously.

### The Accumulation Model

```
Day 1: Developer uses Numpy.fft           → Cache: [fft]
Day 2: Developer adds Numpy.ifft          → Cache: [fft, ifft]
Day 3: Developer stops using fft          → Cache: [fft, ifft]  (unchanged)
Day 4: Developer explicitly prunes        → Cache: [ifft]
```

The cache is a **development artifact** that records everything you've ever used. It's your project's memory of its Python dependencies.

## Cache Structure

### Directory Layout

```
_build/snakebridge/
├── cache.manifest          # Index of all cached entries
├── libraries/
│   ├── numpy/
│   │   ├── meta.json       # Library metadata
│   │   ├── functions/
│   │   │   ├── array_1.beam     # Compiled bytecode
│   │   │   ├── array_1.ex       # Source (for debugging)
│   │   │   ├── array_1.json     # Introspection data
│   │   │   ├── zeros_2.beam
│   │   │   └── ...
│   │   └── classes/
│   │       ├── ndarray.beam
│   │       └── ...
│   ├── pandas/
│   │   └── ...
│   └── json/
│       └── ...
├── docs/
│   ├── numpy_array_1.md    # Cached documentation
│   └── ...
└── stats.json              # Usage statistics
```

### Manifest File

```json
{
  "version": "3.0.0",
  "created_at": "2025-12-25T10:00:00Z",
  "updated_at": "2025-12-25T14:30:00Z",
  "entries": {
    "Numpy.array/1": {
      "library": "numpy",
      "library_version": "1.26.4",
      "generated_at": "2025-12-25T10:05:00Z",
      "last_used": "2025-12-25T14:30:00Z",
      "use_count": 47,
      "beam_file": "libraries/numpy/functions/array_1.beam",
      "source_file": "libraries/numpy/functions/array_1.ex",
      "checksum": "sha256:abc123..."
    },
    "Numpy.zeros/2": {
      "library": "numpy",
      "library_version": "1.26.4",
      "generated_at": "2025-12-25T10:05:30Z",
      "last_used": "2025-12-25T12:00:00Z",
      "use_count": 12,
      "beam_file": "libraries/numpy/functions/zeros_2.beam",
      "source_file": "libraries/numpy/functions/zeros_2.ex",
      "checksum": "sha256:def456..."
    }
  }
}
```

## Cache Operations

### Write (Accumulation)

```elixir
defmodule SnakeBridge.Cache do
  def put(module, function, arity, data) do
    key = cache_key(module, function, arity)
    entry = %{
      library: data.library,
      library_version: data.version,
      generated_at: DateTime.utc_now(),
      last_used: DateTime.utc_now(),
      use_count: 1,
      beam_file: write_beam(key, data.bytecode),
      source_file: write_source(key, data.source),
      checksum: checksum(data.bytecode)
    }

    update_manifest(fn manifest ->
      Map.put(manifest.entries, key, entry)
    end)

    :ok
  end
end
```

### Read (With Usage Tracking)

```elixir
def get(module, function, arity) do
  key = cache_key(module, function, arity)

  case read_manifest().entries[key] do
    nil ->
      :not_found

    entry ->
      # Update usage stats (async, non-blocking)
      Task.start(fn ->
        update_usage(key)
      end)

      {:ok, load_beam(entry.beam_file)}
  end
end

defp update_usage(key) do
  update_manifest(fn manifest ->
    entry = manifest.entries[key]
    updated = %{entry |
      last_used: DateTime.utc_now(),
      use_count: entry.use_count + 1
    }
    put_in(manifest.entries[key], updated)
  end)
end
```

### Invalidation (Not Deletion)

When a library version changes, entries are marked invalid but not deleted:

```elixir
def invalidate_library(library, new_version) do
  update_manifest(fn manifest ->
    entries = Enum.map(manifest.entries, fn {key, entry} ->
      if entry.library == library and entry.library_version != new_version do
        {key, Map.put(entry, :valid, false)}
      else
        {key, entry}
      end
    end)
    %{manifest | entries: Map.new(entries)}
  end)
end
```

Invalid entries are regenerated on next use, but the old data remains for:
- Debugging version differences
- Rollback scenarios
- Audit trails

## Usage Statistics

The cache tracks comprehensive usage data:

```elixir
iex> SnakeBridge.Cache.stats()
%{
  total_entries: 156,
  valid_entries: 152,
  invalid_entries: 4,
  total_size_mb: 2.3,

  by_library: %{
    "numpy" => %{entries: 85, size_mb: 1.2, last_used: ~U[2025-12-25 14:30:00Z]},
    "pandas" => %{entries: 45, size_mb: 0.8, last_used: ~U[2025-12-25 12:00:00Z]},
    "json" => %{entries: 8, size_mb: 0.1, last_used: ~U[2025-12-25 14:25:00Z]},
    "sympy" => %{entries: 18, size_mb: 0.2, last_used: ~U[2025-12-20 09:00:00Z]}
  },

  usage_patterns: %{
    most_used: [
      {"Numpy.array/1", 523},
      {"Numpy.zeros/2", 234},
      {"Pandas.DataFrame/1", 189}
    ],
    unused_30d: [
      {"Sympy.solve/2", ~U[2025-11-20 10:00:00Z]},
      {"Sympy.simplify/1", ~U[2025-11-18 15:00:00Z]}
    ]
  }
}
```

## Cache Warming

### Development Scenario

During active development, the cache warms naturally:

```
$ mix compile
SnakeBridge: Generated Numpy.array/1 (cache miss)

$ mix compile
SnakeBridge: 0 generated (all cached)

$ # Edit code to use Numpy.dot
$ mix compile
SnakeBridge: Generated Numpy.dot/2 (cache miss)
```

### CI/CD Scenario

For CI, you want a pre-warmed cache:

```yaml
# .github/workflows/ci.yml
jobs:
  build:
    steps:
      - uses: actions/checkout@v3

      - name: Restore SnakeBridge Cache
        uses: actions/cache@v3
        with:
          path: _build/snakebridge
          key: snakebridge-${{ hashFiles('mix.lock') }}
          restore-keys: snakebridge-

      - name: Build
        run: mix compile

      - name: Test
        run: mix test
```

### Production Release

The cache is compiled into releases:

```elixir
# rel/config.exs
release :my_app do
  set overlays: [
    {:copy, "_build/snakebridge", "lib/snakebridge/cache"}
  ]
end
```

Or built into the release BEAM:

```bash
$ MIX_ENV=prod mix release
# Cache is embedded in compiled modules
```

## Sharing Caches

### Team Cache Server (Future)

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Developer A   │────►│  Cache Server   │◄────│   Developer B   │
│                 │     │                 │     │                 │
│ Generates       │     │ Stores shared   │     │ Fetches cached  │
│ Numpy.array/1   │     │ entries         │     │ Numpy.array/1   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

Configuration:
```elixir
config :snakebridge,
  shared_cache: [
    url: "https://cache.mycompany.com/snakebridge",
    auth: {:env, "SNAKEBRIDGE_CACHE_TOKEN"},
    push: true,   # Push local generations
    pull: true    # Pull from server on miss
  ]
```

### Offline Cache Bundles

Export cache for offline use:

```bash
$ mix snakebridge.cache.export --output snakebridge_cache.tar.gz
Exported 156 entries (2.3 MB)

$ mix snakebridge.cache.import snakebridge_cache.tar.gz
Imported 156 entries
```

## Cache Integrity

### Checksums

Every entry is checksummed:

```elixir
def verify_entry(key) do
  entry = get_entry(key)
  beam = File.read!(entry.beam_file)

  if checksum(beam) == entry.checksum do
    :ok
  else
    {:error, :corrupted}
  end
end

def verify_all do
  entries = read_manifest().entries
  corrupted = Enum.filter(entries, fn {key, _} ->
    verify_entry(key) == {:error, :corrupted}
  end)

  if corrupted == [] do
    {:ok, length(entries)}
  else
    {:error, corrupted}
  end
end
```

### Repair

```bash
$ mix snakebridge.cache.verify
Checking 156 entries...
Found 2 corrupted entries:
  - Numpy.fft/2
  - Pandas.merge/4

$ mix snakebridge.cache.repair
Regenerating corrupted entries...
  - Numpy.fft/2 ✓
  - Pandas.merge/4 ✓
Cache repaired.
```

## Memory Considerations

### Lazy Loading

BEAM files are loaded on-demand, not at startup:

```elixir
# First call loads the module
Numpy.array([1, 2, 3])  # Loads numpy/functions/array_1.beam

# Subsequent calls use loaded module
Numpy.array([4, 5, 6])  # Already in memory
```

### Cache Size Limits

Optional size limits with LRU eviction:

```elixir
config :snakebridge,
  cache: [
    max_size_mb: 100,
    eviction: :lru
  ]
```

Note: Eviction only affects in-memory cache, not disk cache.

## Migration and Versioning

### Cache Version Migrations

When SnakeBridge upgrades, cache format may change:

```elixir
defmodule SnakeBridge.Cache.Migrator do
  def migrate do
    current = read_version()

    case current do
      "2.0" -> migrate_2_to_3()
      "3.0" -> :already_current
      nil -> initialize_fresh()
    end
  end

  defp migrate_2_to_3 do
    # v2 caches are incompatible (full generation vs lazy)
    # Clear and start fresh
    Logger.info("Migrating cache from v2 to v3 (full regeneration required)")
    clear_all()
    {:ok, :migrated}
  end
end
```

### Python Library Upgrades

When a library version changes in mix.exs:

```elixir
# mix.exs change: numpy "~> 1.26" → numpy "~> 2.0"

$ mix compile
SnakeBridge: numpy version changed (1.26.4 → 2.0.0)
SnakeBridge: Invalidated 85 numpy entries (will regenerate on use)
```

Entries are invalidated but kept. They're regenerated when used.
