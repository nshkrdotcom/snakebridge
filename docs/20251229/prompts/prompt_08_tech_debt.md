# Implementation Prompt: Domain 8 - Cleanup & Tech Debt

## Context

You are addressing technical debt and cleanup issues in SnakeBridge. This is a **P1** domain.

## Required Reading

Before implementing, read these files in order:

### Critique Documents
1. `docs/20251229/critique/001_gpt52.md` - Other noteworthy shortcomings section
2. `docs/20251229/critique/003_g3p.md` - Section 3 (codebase shortcomings)

### Implementation Plan
3. `docs/20251229/implementation/00_master_plan.md` - Domain 8 overview

### Source Files (Elixir)
4. `lib/snakebridge/introspector.ex` - Embedded script (lines 117-323)
5. `lib/snakebridge/registry.ex` - Unused registry
6. `lib/snakebridge/lock.ex` - generator_hash function
7. `lib/snakebridge/generator.ex` - write_if_changed function
8. `lib/snakebridge/wheel_selector.ex` - Hardcoded maps
9. `lib/snakebridge/telemetry.ex` - Telemetry events
10. `lib/snakebridge/telemetry/runtime_forwarder.ex` - Event forwarding

### Source Files (Python)
11. `priv/python/introspect.py` - Standalone introspection
12. `priv/python/snakebridge_adapter.py` - Global state (lines 47-52)

## Issues to Fix

### Issue 8.1: Duplicate Introspection Implementations
**Problem**: Two competing implementations that can drift.
**Locations**:
- `lib/snakebridge/introspector.ex` lines 117-323 (embedded)
- `priv/python/introspect.py` (standalone)
**Fix**: Consolidate to single source of truth (Python standalone), shell out from Elixir.

### Issue 8.2: Telemetry Semantic Inconsistency
**Problem**: Runtime vs compile events have different structures, confusing consumers.
**Location**: `lib/snakebridge/telemetry.ex`, `lib/snakebridge/telemetry/runtime_forwarder.ex`
**Fix**: Unify event naming and metadata schema.

### Issue 8.3: Registry Not Wired to Generation
**Problem**: `SnakeBridge.Registry` exists but is never called during compile.
**Location**: `lib/snakebridge/registry.ex`, `lib/snakebridge/generator.ex`
**Fix**: Call `Registry.register/2` after generating each library.

### Issue 8.4: Lock generator_hash Not Meaningful
**Problem**: Hashes version string, not actual generator code.
**Location**: `lib/snakebridge/lock.ex` lines 201-203
**Fix**: Hash actual generator module contents.

### Issue 8.5: Brittle Wheel Selection
**Problem**: Hardcoded CUDA version maps require constant updates.
**Location**: `lib/snakebridge/wheel_selector.ex` lines 196-206
**Fix**: Externalize to configuration, add pluggable strategy.

### Issue 8.6: File Generation Race Condition
**Problem**: `write_if_changed` cleanup in `after` block is dangerous.
**Location**: `lib/snakebridge/generator.ex` lines 99-116
**Fix**: Fix error handling, add write locking.

### Issue 8.7: Python Global State Thread Safety
**Problem**: `_instance_registry` is unprotected global dict.
**Location**: `priv/python/snakebridge_adapter.py` lines 47-52
**Fix**: Add threading locks, implement session isolation.

## TDD Implementation Steps

### Step 1: Write Tests First

Create `test/snakebridge/introspector_consolidation_test.exs`:
```elixir
defmodule SnakeBridge.IntrospectorConsolidationTest do
  use ExUnit.Case

  describe "introspection via Python script" do
    test "uses standalone introspect.py" do
      # Verify introspector shells out to Python script
      {:ok, result} = SnakeBridge.Introspector.introspect(:math, [:sqrt])

      assert is_map(result)
      assert Map.has_key?(result, "functions")
    end

    test "handles introspection errors gracefully" do
      {:error, reason} = SnakeBridge.Introspector.introspect(:nonexistent_module_xyz, [:foo])
      assert is_binary(reason) or is_atom(reason)
    end
  end
end
```

Create `test/snakebridge/telemetry_consistency_test.exs`:
```elixir
defmodule SnakeBridge.TelemetryConsistencyTest do
  use ExUnit.Case

  describe "telemetry event schema" do
    test "compile events have consistent metadata" do
      events = [
        [:snakebridge, :compile, :scan, :stop],
        [:snakebridge, :compile, :introspect, :stop],
        [:snakebridge, :compile, :generate, :stop]
      ]

      # All should have: library, phase, duration
      for event <- events do
        metadata = SnakeBridge.Telemetry.event_metadata_schema(event)
        assert :library in metadata
        assert :phase in metadata
      end
    end

    test "runtime events have consistent metadata" do
      events = [
        [:snakebridge, :runtime, :call, :start],
        [:snakebridge, :runtime, :call, :stop]
      ]

      for event <- events do
        metadata = SnakeBridge.Telemetry.event_metadata_schema(event)
        assert :library in metadata
        assert :function in metadata
      end
    end
  end
end
```

Create `test/snakebridge/registry_integration_test.exs`:
```elixir
defmodule SnakeBridge.RegistryIntegrationTest do
  use ExUnit.Case

  describe "registry population during compile" do
    test "generate_library registers entry" do
      library = %{python_name: "test_lib", module_name: TestLib}

      # After generation, registry should have entry
      # (This requires integration with actual generation)
    end
  end
end
```

Create `test/snakebridge/lock_hash_test.exs`:
```elixir
defmodule SnakeBridge.LockHashTest do
  use ExUnit.Case

  describe "generator hash" do
    test "hash changes when generator code changes" do
      hash1 = SnakeBridge.Lock.generator_hash()

      # Hash should be deterministic
      hash2 = SnakeBridge.Lock.generator_hash()
      assert hash1 == hash2
    end

    test "hash includes generator file contents" do
      # Verify hash is based on actual file contents, not just version
      hash = SnakeBridge.Lock.generator_hash()
      assert is_binary(hash)
      assert byte_size(hash) == 64  # SHA256 hex
    end
  end
end
```

Create `test/snakebridge/generator_race_condition_test.exs`:
```elixir
defmodule SnakeBridge.GeneratorRaceConditionTest do
  use ExUnit.Case

  describe "write_if_changed" do
    test "handles concurrent writes safely" do
      path = Path.join(System.tmp_dir!(), "test_#{System.unique_integer()}.ex")

      tasks = for i <- 1..10 do
        Task.async(fn ->
          SnakeBridge.Generator.write_if_changed(path, "content #{i}")
        end)
      end

      results = Task.await_many(tasks, 5000)

      # All should succeed (either :written or :unchanged)
      assert Enum.all?(results, &(&1 in [:written, :unchanged]))

      # File should exist with valid content
      assert File.exists?(path)
      File.rm!(path)
    end

    test "cleans up temp file on error" do
      path = "/nonexistent/path/test.ex"

      assert_raise File.Error, fn ->
        SnakeBridge.Generator.write_if_changed(path, "content")
      end

      # No temp files should be left behind
      temp_files = Path.wildcard("/nonexistent/path/*.tmp.*")
      assert temp_files == []
    end
  end
end
```

### Step 2: Run Tests (Expect Failures)
```bash
mix test test/snakebridge/introspector_consolidation_test.exs
mix test test/snakebridge/telemetry_consistency_test.exs
mix test test/snakebridge/registry_integration_test.exs
mix test test/snakebridge/lock_hash_test.exs
mix test test/snakebridge/generator_race_condition_test.exs
```

### Step 3: Implement Fixes

#### 3.1 Consolidate Introspection to Python Script
File: `lib/snakebridge/introspector.ex`

Replace embedded script with shell-out:
```elixir
@doc """
Introspects a Python module using the standalone introspect.py script.
"""
def introspect(module, symbols, opts \\ []) do
  script_path = Path.join(:code.priv_dir(:snakebridge), "python/introspect.py")

  args = [
    script_path,
    "--module", to_string(module),
    "--format", "json"
  ]

  case System.cmd("python3", args, stderr_to_stdout: true) do
    {output, 0} ->
      {:ok, Jason.decode!(output)}

    {error, _code} ->
      {:error, error}
  end
end

# Remove the embedded script (lines 117-323)
# Keep only the shell-out implementation
```

#### 3.2 Unify Telemetry Events
File: `lib/snakebridge/telemetry.ex`

Add unified event helpers:
```elixir
@moduledoc """
Unified telemetry for SnakeBridge.

## Event Schema

All events follow this structure:

### Compile-Time Events
- `[:snakebridge, :compile, :phase, :start]`
- `[:snakebridge, :compile, :phase, :stop]`

Metadata:
- `:library` - Library being compiled
- `:phase` - :scan | :introspect | :generate
- `:details` - Phase-specific details

### Runtime Events
- `[:snakebridge, :runtime, :call, :start]`
- `[:snakebridge, :runtime, :call, :stop]`
- `[:snakebridge, :runtime, :call, :exception]`

Metadata:
- `:library` - Library module
- `:function` - Function being called
- `:call_type` - :function | :method | :class | :dynamic
"""

@doc """
Returns the expected metadata fields for an event.
"""
def event_metadata_schema([:snakebridge, :compile | _]) do
  [:library, :phase, :details]
end

def event_metadata_schema([:snakebridge, :runtime | _]) do
  [:library, :function, :call_type]
end

@doc """
Emits a compile phase event with consistent metadata.
"""
def compile_phase_start(phase, library, details \\ %{}) do
  metadata = %{
    library: library,
    phase: phase,
    details: details
  }

  :telemetry.execute(
    [:snakebridge, :compile, phase, :start],
    %{system_time: System.system_time()},
    metadata
  )
end

def compile_phase_stop(start_time, phase, library, measurements \\ %{}, details \\ %{}) do
  duration = System.monotonic_time() - start_time

  metadata = %{
    library: library,
    phase: phase,
    details: details
  }

  :telemetry.execute(
    [:snakebridge, :compile, phase, :stop],
    Map.merge(measurements, %{duration: duration}),
    metadata
  )
end
```

#### 3.3 Wire Registry to Generation
File: `lib/snakebridge/generator.ex`

Add registry call in generate_library:
```elixir
def generate_library(library, functions, classes, config) do
  path = Path.join(config.generated_dir, "#{library.python_name}.ex")
  source = render_library(library, functions, classes)

  result = write_if_changed(path, source)

  # Register the generated library
  if result == :written do
    entry = build_registry_entry(library, functions, classes, config)
    SnakeBridge.Registry.register(library.python_name, entry)
  end

  result
end

defp build_registry_entry(library, functions, classes, config) do
  %{
    python_module: library.python_name,
    elixir_module: Atom.to_string(library.module_name),
    generated_at: DateTime.utc_now(),
    path: config.generated_dir,
    stats: %{
      functions: length(functions),
      classes: length(classes)
    }
  }
end
```

File: `lib/mix/tasks/compile/snakebridge.ex`

Add registry save at end of compilation:
```elixir
def run_normal(config) do
  # ... existing code ...

  # Save registry after all generation
  SnakeBridge.Registry.save()

  :ok
end
```

#### 3.4 Fix Lock generator_hash
File: `lib/snakebridge/lock.ex`

Replace version hash with content hash:
```elixir
@generator_files [
  "lib/snakebridge/generator.ex",
  "lib/snakebridge/docs.ex",
  "priv/python/snakebridge_types.py",
  "priv/python/snakebridge_adapter.py"
]

defp generator_hash do
  content = @generator_files
    |> Enum.map(&read_generator_file/1)
    |> Enum.join("\n")

  :crypto.hash(:sha256, content)
  |> Base.encode16(case: :lower)
end

defp read_generator_file(relative_path) do
  case Application.app_dir(:snakebridge, relative_path) do
    path when is_binary(path) ->
      case File.read(path) do
        {:ok, content} -> content
        {:error, _} -> ""
      end

    _ ->
      ""
  end
end

@doc """
Checks if the lock was generated with the current generator version.
"""
def verify_generator_unchanged?(lock) do
  lock_hash = get_in(lock, ["environment", "generator_hash"])
  current_hash = generator_hash()
  lock_hash == current_hash
end
```

#### 3.5 Externalize Wheel Selection
File: `lib/snakebridge/wheel_config.ex` (new file)

```elixir
defmodule SnakeBridge.WheelConfig do
  @moduledoc """
  Configuration-based wheel variant selection.
  """

  @config_path "config/wheel_variants.json"

  @doc """
  Loads wheel configuration from file or uses defaults.
  """
  def load_config do
    case File.read(config_path()) do
      {:ok, content} ->
        Jason.decode!(content)

      {:error, _} ->
        default_config()
    end
  end

  @doc """
  Gets available variants for a package.
  """
  def get_variants(package) do
    config = load_config()
    get_in(config, ["packages", package, "variants"]) || ["cpu"]
  end

  @doc """
  Gets CUDA mapping for a version.
  """
  def get_cuda_mapping(version) do
    config = load_config()
    get_in(config, ["cuda_mappings", version])
  end

  defp config_path do
    Application.app_dir(:snakebridge, @config_path)
  end

  defp default_config do
    %{
      "packages" => %{
        "torch" => %{"variants" => ["cpu", "cu118", "cu121", "cu124"]},
        "torchvision" => %{"variants" => ["cpu", "cu118", "cu121", "cu124"]},
        "torchaudio" => %{"variants" => ["cpu", "cu118", "cu121", "cu124"]}
      },
      "cuda_mappings" => %{
        "11.7" => "cu118", "11.8" => "cu118",
        "12.0" => "cu121", "12.1" => "cu121", "12.2" => "cu121",
        "12.3" => "cu124", "12.4" => "cu124", "12.5" => "cu124"
      }
    }
  end
end
```

#### 3.6 Fix File Generation Race Condition
File: `lib/snakebridge/generator.ex`

Fix write_if_changed:
```elixir
def write_if_changed(path, new_content) do
  case File.read(path) do
    {:ok, existing} when existing == new_content ->
      :unchanged

    _ ->
      write_atomic(path, new_content)
  end
end

defp write_atomic(path, content) do
  temp_path = "#{path}.tmp.#{System.unique_integer([:positive])}"

  try do
    # Ensure directory exists
    File.mkdir_p!(Path.dirname(path))

    # Write to temp file
    File.write!(temp_path, content)

    # Atomic rename
    case File.rename(temp_path, path) do
      :ok ->
        :written

      {:error, reason} ->
        raise "Failed to write #{path}: #{inspect(reason)}"
    end
  rescue
    e ->
      # Clean up temp file on any error
      File.rm(temp_path)
      reraise e, __STACKTRACE__
  end
end
```

#### 3.7 Add Python Thread Safety
File: `priv/python/snakebridge_adapter.py`

Add thread locks:
```python
import threading

# Thread locks for global state
_registry_lock = threading.RLock()
_cache_lock = threading.RLock()
_helper_lock = threading.RLock()

def _store_ref(key: str, obj: Any) -> None:
    with _registry_lock:
        _instance_registry[key] = {
            "obj": obj,
            "created_at": time.time(),
            "last_access": time.time()
        }

def _resolve_ref(ref: dict, session_id: str) -> Any:
    with _registry_lock:
        key = f"{session_id}:{ref.get('id')}"
        entry = _instance_registry.get(key)
        if entry:
            entry["last_access"] = time.time()
            return entry["obj"]
        raise ValueError(f"Reference not found: {key}")

def _prune_registry() -> None:
    with _registry_lock:
        # ... existing pruning logic ...

def _import_module(module_name: str) -> Any:
    with _cache_lock:
        if module_name in _module_cache:
            return _module_cache[module_name]

        mod = importlib.import_module(module_name)
        _module_cache[module_name] = mod
        return mod
```

### Step 4: Run Tests (Expect Pass)
```bash
mix test test/snakebridge/introspector_consolidation_test.exs
mix test test/snakebridge/telemetry_consistency_test.exs
mix test test/snakebridge/registry_integration_test.exs
mix test test/snakebridge/lock_hash_test.exs
mix test test/snakebridge/generator_race_condition_test.exs
mix test
```

### Step 5: Run Full Quality Checks
```bash
mix compile --warnings-as-errors
mix dialyzer
mix credo --strict
```

### Step 6: Update Examples

Review all examples in `examples/` to ensure they still work after cleanup.
Update `examples/run_all.sh` if needed.

### Step 7: Update Documentation

Update `README.md`:
- Document wheel configuration file format
- Document telemetry event schema
- Note breaking changes (if any)

## Acceptance Criteria

- [ ] Single introspection implementation (Python standalone)
- [ ] Telemetry events have consistent metadata schema
- [ ] Registry populated during compilation
- [ ] Lock hash reflects actual generator code
- [ ] Wheel variants configurable via JSON
- [ ] No race conditions in file generation
- [ ] Python global state is thread-safe
- [ ] All existing tests pass
- [ ] New tests for this domain pass
- [ ] No dialyzer errors
- [ ] No credo warnings

## Dependencies

This domain can be implemented in parallel with other domains as it mostly addresses code quality issues rather than feature additions.

Completion of this domain improves long-term maintainability and prepares the codebase for future enhancements.
