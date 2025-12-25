# SnakeBridge Registry API Reference

**Version**: 2.1
**Module**: `SnakeBridge.Registry`
**Status**: ✅ Complete and Tested

## Overview

The Registry provides a simple, file-based system for tracking generated Python library adapters. It uses an Agent for concurrent access and persists to JSON for durability.

## API Functions

### `list_libraries/0`

Returns a sorted list of all registered library names.

```elixir
SnakeBridge.Registry.list_libraries()
# => ["json", "numpy", "sympy"]
```

**Returns**: `[String.t()]`

---

### `get/1`

Gets detailed information about a registered library.

```elixir
SnakeBridge.Registry.get("numpy")
# => %{
#   python_module: "numpy",
#   python_version: "1.26.0",
#   elixir_module: "Numpy",
#   generated_at: ~U[2024-12-24 14:00:00Z],
#   path: "lib/snakebridge/adapters/numpy/",
#   files: ["numpy.ex", "linalg.ex", "_meta.ex"],
#   stats: %{functions: 165, classes: 2, submodules: 4}
# }

SnakeBridge.Registry.get("nonexistent")
# => nil
```

**Parameters**:
- `library_name` - String identifier for the library

**Returns**: `registry_entry() | nil`

---

### `generated?/1`

Checks if a library is registered.

```elixir
SnakeBridge.Registry.generated?("numpy")
# => true

SnakeBridge.Registry.generated?("nonexistent")
# => false
```

**Parameters**:
- `library_name` - String identifier for the library

**Returns**: `boolean()`

---

### `register/2`

Registers or updates a library entry. Validates the entry structure.

```elixir
entry = %{
  python_module: "numpy",
  python_version: "1.26.0",
  elixir_module: "Numpy",
  generated_at: DateTime.utc_now(),
  path: "lib/snakebridge/adapters/numpy/",
  files: ["numpy.ex", "linalg.ex", "_meta.ex"],
  stats: %{functions: 165, classes: 2, submodules: 4}
}

SnakeBridge.Registry.register("numpy", entry)
# => :ok

# Invalid entry
SnakeBridge.Registry.register("bad", %{python_module: "bad"})
# => {:error, "Missing required fields: [...]}"}
```

**Parameters**:
- `library_name` - String identifier for the library
- `entry` - Map containing library information (see Entry Format below)

**Returns**: `:ok | {:error, String.t()}`

---

### `unregister/1`

Removes a library from the registry.

```elixir
SnakeBridge.Registry.unregister("numpy")
# => :ok

# Returns :ok even if library doesn't exist
SnakeBridge.Registry.unregister("nonexistent")
# => :ok
```

**Parameters**:
- `library_name` - String identifier for the library

**Returns**: `:ok`

---

### `clear/0`

Removes all entries from the registry.

```elixir
SnakeBridge.Registry.clear()
# => :ok
```

**Returns**: `:ok`

---

### `save/0`

Persists the registry to `priv/snakebridge/registry.json`. Creates parent directories if needed.

```elixir
SnakeBridge.Registry.save()
# => :ok
```

**Returns**: `:ok | {:error, term()}`

---

### `load/0`

Loads the registry from `priv/snakebridge/registry.json`. If the file doesn't exist, initializes an empty registry.

```elixir
SnakeBridge.Registry.load()
# => :ok

# Handles missing files gracefully
SnakeBridge.Registry.load()  # file doesn't exist
# => :ok  (empty registry)

# Returns error for corrupted JSON
SnakeBridge.Registry.load()  # corrupt JSON
# => {:error, reason}
```

**Returns**: `:ok | {:error, term()}`

---

## Entry Format

Registry entries must include all required fields:

```elixir
%{
  # Required fields
  python_module: String.t(),    # e.g., "numpy"
  python_version: String.t(),   # e.g., "1.26.0"
  elixir_module: String.t(),    # e.g., "Numpy"
  generated_at: DateTime.t(),   # Generation timestamp
  path: String.t(),             # Directory path
  files: [String.t()],          # List of generated files
  stats: %{
    functions: non_neg_integer(),   # Function count
    classes: non_neg_integer(),     # Class count
    submodules: non_neg_integer()   # Submodule count
  }
}
```

## JSON File Format

The registry is persisted to `priv/snakebridge/registry.json`:

```json
{
  "version": "2.1",
  "generated_at": "2024-12-24T15:00:00Z",
  "libraries": {
    "numpy": {
      "python_module": "numpy",
      "python_version": "1.26.0",
      "elixir_module": "Numpy",
      "generated_at": "2024-12-24T14:00:00Z",
      "path": "lib/snakebridge/adapters/numpy/",
      "files": ["numpy.ex", "linalg.ex", "_meta.ex"],
      "stats": {
        "functions": 165,
        "classes": 2,
        "submodules": 4
      }
    }
  }
}
```

## Configuration

The registry file path can be configured in `config/config.exs`:

```elixir
config :snakebridge,
  registry_path: "priv/snakebridge/registry.json"
```

Default: `priv/snakebridge/registry.json`

## Concurrency

The Registry uses an Agent for concurrent access, making it safe to use from multiple processes:

```elixir
# Safe concurrent access
tasks = for i <- 1..100 do
  Task.async(fn ->
    SnakeBridge.Registry.register("lib#{i}", entry)
  end)
end

Task.await_many(tasks)
```

## Error Handling

All functions handle errors gracefully:

- `load/0` - Returns `:ok` if file missing, `{:error, reason}` if corrupt
- `save/0` - Returns `{:error, reason}` if write fails
- `register/2` - Returns `{:error, reason}` if entry invalid
- `get/1` - Returns `nil` if library not found (not an error)

## Examples

### Basic Workflow

```elixir
alias SnakeBridge.Registry

# Register a library
entry = %{
  python_module: "requests",
  python_version: "2.31.0",
  elixir_module: "Requests",
  generated_at: DateTime.utc_now(),
  path: "lib/snakebridge/adapters/requests/",
  files: ["requests.ex", "_meta.ex"],
  stats: %{functions: 12, classes: 3, submodules: 1}
}

Registry.register("requests", entry)

# Check registration
Registry.generated?("requests")
# => true

# Persist to disk
Registry.save()

# Later: load from disk
Registry.load()
```

### Updating an Entry

```elixir
# Register initial version
entry_v1 = %{..., python_version: "2.30.0", ...}
Registry.register("requests", entry_v1)

# Update to new version
entry_v2 = %{..., python_version: "2.31.0", ...}
Registry.register("requests", entry_v2)

# Entry is updated, not duplicated
Registry.get("requests").python_version
# => "2.31.0"
```

### Bulk Operations

```elixir
# Register multiple libraries
libraries = ["numpy", "requests", "json", "sympy"]
for lib <- libraries do
  Registry.register(lib, build_entry(lib))
end

# List all
Registry.list_libraries()
# => ["json", "numpy", "requests", "sympy"]

# Clear all
Registry.clear()
```

## Integration with Mix Tasks

The Registry is designed to integrate with v2.1 Mix tasks:

```elixir
# In mix snakebridge.gen
defp register_generated_library(lib_name, files, stats) do
  entry = %{
    python_module: lib_name,
    python_version: get_python_version(lib_name),
    elixir_module: Macro.camelize(lib_name),
    generated_at: DateTime.utc_now(),
    path: "lib/snakebridge/adapters/#{lib_name}/",
    files: files,
    stats: stats
  }

  SnakeBridge.Registry.register(lib_name, entry)
  SnakeBridge.Registry.save()
end

# In mix snakebridge.list
def run(_args) do
  Application.ensure_all_started(:snakebridge)

  SnakeBridge.Registry.list_libraries()
  |> Enum.each(fn lib ->
    info = SnakeBridge.Registry.get(lib)
    Mix.shell().info("#{lib} (#{info.stats.functions} functions)")
  end)
end

# In mix snakebridge.remove
def run([library_name]) do
  Application.ensure_all_started(:snakebridge)

  if SnakeBridge.Registry.generated?(library_name) do
    info = SnakeBridge.Registry.get(library_name)
    File.rm_rf!(info.path)
    SnakeBridge.Registry.unregister(library_name)
    SnakeBridge.Registry.save()
  end
end
```

## See Also

- [SnakeBridge v2.1 Requirements](snakebridge-v2-architecture/11-v2.1-requirements.md)
- Module documentation: `h SnakeBridge.Registry`
- Test suite: `test/snakebridge/registry_test.exs`
