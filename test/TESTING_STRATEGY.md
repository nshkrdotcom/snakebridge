# SnakeBridge Testing & Mocking Strategy

**Version**: 1.0
**Date**: 2025-10-25

---

## Overview

SnakeBridge testing follows a **layered strategy** that separates pure Elixir logic from external dependencies (Snakepit/Python).

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 6: Developer Tools (Mix Tasks, LSP)                  │
│  Testing: Integration tests with file fixtures              │
│  Mocking: None (uses real file system)                      │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│  Layer 5: Generated Modules                                 │
│  Testing: Runtime compilation tests                         │
│  Mocking: Mock the Runtime.Executor protocol                │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│  Layer 4: Code Generation Engine                            │
│  Testing: AST generation, macro expansion                   │
│  Mocking: None (pure Elixir code)                           │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│  Layer 3: Schema & Type System                              │
│  Testing: Unit tests for diffing, validation, inference     │
│  Mocking: None (pure Elixir functions)                      │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│  Layer 2: Discovery & Introspection                         │
│  Testing: Mock Python introspection responses               │
│  Mocking: Mock Snakepit.execute_in_session                  │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: Execution Runtime                                 │
│  Testing: Mock Snakepit, real integration tests tagged      │
│  Mocking: Mock Snakepit.execute_in_session                  │
└─────────────────────────────────────────────────────────────┘
```

---

## Three-Tier Testing Strategy

### Tier 1: Unit Tests (Fast, Pure Elixir)

**What we test**:
- Config validation, composition, hashing
- Type system mapping (Python ↔ Elixir)
- Schema diffing algorithms
- Code generation (AST manipulation)
- Cache operations (ETS)

**No mocking needed** - these are pure Elixir functions:
- `SnakeBridge.Config` ✅
- `SnakeBridge.TypeSystem.Mapper` ✅
- `SnakeBridge.Schema.Differ` ✅
- `SnakeBridge.Cache` ✅

**Why no mocks?**
- No external dependencies
- Deterministic inputs → outputs
- Fast (<1ms per test)
- No I/O, no network, no processes

**Example**:
```elixir
test "hash is consistent for same config" do
  config = %SnakeBridge.Config{python_module: "dspy"}

  hash1 = SnakeBridge.Config.hash(config)
  hash2 = SnakeBridge.Config.hash(config)

  assert hash1 == hash2  # Pure function, no mocks needed
end
```

---

### Tier 2: Integration Tests (Medium, Mocked Boundaries)

**What we test**:
- Discovery workflow (Config → Introspection → Generated modules)
- Code generation → Runtime compilation
- End-to-end without real Python

**Mocking strategy**: Mock the **Snakepit boundary** using Mox

**Mock**: `Snakepit.execute_in_session/3`

```elixir
defmodule SnakeBridge.SnakepitMock do
  @moduledoc """
  Mock implementation of Snakepit for testing.

  Mocks ONLY the boundary functions we call, not internal Snakepit behavior.
  """

  @doc """
  Mock Snakepit.execute_in_session/3 for testing.

  Returns canned responses based on tool_name:
  - "describe_library" → Python introspection response
  - "call_dspy" → Fake Python execution result
  - etc.
  """
  def execute_in_session(_session_id, tool_name, args) do
    case tool_name do
      "describe_library" ->
        {:ok, SnakeBridge.TestFixtures.sample_introspection_response()}

      "call_dspy" ->
        case args do
          %{"function_name" => "__init__"} ->
            {:ok, %{"success" => true, "instance_id" => "test_instance_123"}}

          %{"function_name" => "__call__"} ->
            {:ok, %{"success" => true, "result" => %{"answer" => "test response"}}}

          _ ->
            {:ok, %{"success" => true, "result" => "generic"}}
        end

      _ ->
        {:error, "Unknown tool: #{tool_name}"}
    end
  end
end
```

**Usage in tests**:
```elixir
# In test_helper.exs
Mox.defmock(SnakeBridge.SnakepitMock, for: SnakeBridge.SnakepitBehaviour)

# In tests
import Mox

test "discovers library and generates modules" do
  # Arrange: Set up mock expectations
  expect(SnakeBridge.SnakepitMock, :execute_in_session, fn _session, "describe_library", _args ->
    {:ok, TestFixtures.sample_introspection_response()}
  end)

  # Act: Run discovery (will call mocked Snakepit)
  {:ok, schema} = SnakeBridge.Discovery.discover("dspy", snakepit: SnakeBridge.SnakepitMock)

  # Assert
  assert schema["library_version"] == "2.5.0"
end
```

**What gets mocked**:
- ✅ `Snakepit.execute_in_session/3` - Main execution boundary
- ✅ `Snakepit.execute_in_session/4` - With timeout
- ❌ Internal Snakepit logic (session store, gRPC, etc.) - Not our concern

---

### Tier 3: Real Integration Tests (Slow, External Dependencies)

**What we test**:
- **REAL** Snakepit + Python interaction
- **REAL** DSPy library introspection
- **REAL** code execution and streaming

**No mocking** - actual Python execution

**Tagging strategy**:
```elixir
@moduletag :integration  # Skipped by default
@moduletag :external     # Requires external services
@moduletag :slow         # Takes >100ms

test "actually introspects DSPy from Python" do
  # Uses REAL Snakepit, REAL Python worker
  {:ok, schema} = SnakeBridge.Discovery.discover_real("dspy")

  assert schema["library_version"] =~ "2."
  assert Map.has_key?(schema["classes"], "Predict")
end
```

**Run these separately**:
```bash
# Normal testing (fast, mocked)
mix test

# Integration testing (slow, real Python)
mix test --only integration
mix test --only external
```

---

## Mocking Implementation Plan

### Step 1: Define Snakepit Behaviour

```elixir
# lib/snakebridge/snakepit_behaviour.ex

defmodule SnakeBridge.SnakepitBehaviour do
  @moduledoc """
  Behaviour that wraps Snakepit functions we depend on.

  This allows us to mock Snakepit in tests while using the real
  implementation in production.
  """

  @callback execute_in_session(
    session_id :: String.t(),
    tool_name :: String.t(),
    args :: map()
  ) :: {:ok, map()} | {:error, term()}

  @callback execute_in_session(
    session_id :: String.t(),
    tool_name :: String.t(),
    args :: map(),
    opts :: keyword()
  ) :: {:ok, map()} | {:error, term()}

  @callback get_stats() :: map()
end
```

### Step 2: Create Real Adapter

```elixir
# lib/snakebridge/snakepit_adapter.ex

defmodule SnakeBridge.SnakepitAdapter do
  @moduledoc """
  Real implementation that delegates to Snakepit.

  This is the production adapter - no mocking, just delegates
  to actual Snakepit functions.
  """

  @behaviour SnakeBridge.SnakepitBehaviour

  @impl true
  def execute_in_session(session_id, tool_name, args) do
    Snakepit.execute_in_session(session_id, tool_name, args)
  end

  @impl true
  def execute_in_session(session_id, tool_name, args, opts) do
    Snakepit.execute_in_session(session_id, tool_name, args, opts)
  end

  @impl true
  def get_stats do
    Snakepit.get_stats()
  end
end
```

### Step 3: Create Mock for Testing

```elixir
# test/support/snakepit_mock.ex

defmodule SnakeBridge.SnakepitMock do
  @moduledoc """
  Mock implementation of Snakepit for testing.

  Returns canned responses based on tool_name and args.
  """

  @behaviour SnakeBridge.SnakepitBehaviour

  @impl true
  def execute_in_session(session_id, tool_name, args, _opts \\ []) do
    case tool_name do
      "describe_library" ->
        describe_library_response(args)

      "call_dspy" ->
        call_dspy_response(args)

      "batch_execute" ->
        batch_execute_response(args)

      _ ->
        {:error, "Unknown tool: #{tool_name}"}
    end
  end

  @impl true
  def get_stats do
    %{
      active_sessions: 0,
      available_workers: 4,
      queued_requests: 0
    }
  end

  # Private response generators

  defp describe_library_response(%{"module_path" => "dspy"}) do
    {:ok, %{
      "success" => true,
      "library_version" => "2.5.0",
      "classes" => %{
        "Predict" => %{
          "name" => "Predict",
          "python_path" => "dspy.Predict",
          "docstring" => "Basic prediction module",
          "methods" => [
            %{"name" => "__call__", "supports_streaming" => false}
          ]
        }
      },
      "functions" => %{},
      "descriptor_hash" => "abc123"
    }}
  end

  defp describe_library_response(_) do
    {:error, "Module not found"}
  end

  defp call_dspy_response(%{"function_name" => "__init__"}) do
    {:ok, %{
      "success" => true,
      "instance_id" => "mock_instance_#{:rand.uniform(1000)}"
    }}
  end

  defp call_dspy_response(%{"function_name" => "__call__"}) do
    {:ok, %{
      "success" => true,
      "result" => %{"answer" => "Mocked response"}
    }}
  end

  defp call_dspy_response(_) do
    {:ok, %{"success" => true, "result" => %{}}}
  end

  defp batch_execute_response(%{"operations" => operations}) do
    results = Enum.map(operations, fn _op ->
      %{"success" => true, "result" => %{}}
    end)

    {:ok, %{"success" => true, "results" => results}}
  end
end
```

### Step 4: Configure in Runtime Module

```elixir
# lib/snakebridge/runtime.ex

defmodule SnakeBridge.Runtime do
  @moduledoc """
  Runtime execution layer for SnakeBridge.

  Handles interaction with Snakepit, with configurable adapter
  for testing vs production.
  """

  @doc """
  Get the configured Snakepit adapter.

  Returns mock in test, real adapter in dev/prod.
  """
  def snakepit_adapter do
    Application.get_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitAdapter)
  end

  @doc """
  Execute a tool via Snakepit.
  """
  def execute(session_id, tool_name, args, opts \\ []) do
    adapter = snakepit_adapter()
    adapter.execute_in_session(session_id, tool_name, args, opts)
  end
end
```

### Step 5: Configure in Test

```elixir
# config/test.exs

import Config

config :snakebridge,
  # Use mock in tests
  snakepit_adapter: SnakeBridge.SnakepitMock,
  compilation_strategy: :runtime,
  cache_enabled: false,
  telemetry_enabled: false
```

```elixir
# config/dev.exs

import Config

config :snakebridge,
  # Use real Snakepit in dev
  snakepit_adapter: SnakeBridge.SnakepitAdapter,
  compilation_strategy: :runtime,
  cache_enabled: true
```

---

## Testing Layers

### Layer 1: Pure Elixir (No Mocking)

**Modules**:
- `SnakeBridge.Config`
- `SnakeBridge.TypeSystem.Mapper`
- `SnakeBridge.Schema.Differ`
- `SnakeBridge.Cache` (ETS is real, not mocked)

**Strategy**: Direct testing, no mocks

```elixir
test "validates config" do
  config = %SnakeBridge.Config{python_module: "test"}
  assert {:ok, _} = SnakeBridge.Config.validate(config)
  # No mocks - pure validation logic
end
```

**Benefits**:
- Fast (microseconds)
- Deterministic
- No test coupling
- High confidence

---

### Layer 2: Snakepit Boundary (Mocked)

**Modules**:
- `SnakeBridge.Discovery.Introspector`
- `SnakeBridge.Runtime.Executor`

**Strategy**: Mock `Snakepit.execute_in_session` via adapter pattern

**Implementation**:

```elixir
# lib/snakebridge/discovery/introspector.ex

defmodule SnakeBridge.Discovery.Introspector do
  @doc """
  Discover library schema via Snakepit.
  """
  def discover(module_path, opts \\ []) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    adapter = SnakeBridge.Runtime.snakepit_adapter()

    # Call through adapter (mocked in tests, real in prod)
    case adapter.execute_in_session(session_id, "describe_library", %{
      "module_path" => module_path,
      "discovery_depth" => Keyword.get(opts, :depth, 2)
    }) do
      {:ok, %{"success" => true} = response} ->
        {:ok, response}

      {:ok, %{"success" => false, "error" => error}} ->
        {:error, error}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

**Test**:
```elixir
test "discovers library schema" do
  # Mock returns fake introspection data
  # No real Python execution

  {:ok, schema} = SnakeBridge.Discovery.Introspector.discover("dspy")

  assert schema["library_version"] == "2.5.0"  # From mock
end
```

**Benefits**:
- Tests run without Python
- Fast (milliseconds)
- Controlled responses
- Test edge cases easily

---

### Layer 3: Real Integration (No Mocking)

**Modules**: Full stack

**Strategy**: Real Snakepit + Python, tagged to skip by default

**Implementation**:

```elixir
defmodule SnakeBridge.Integration.RealPythonTest do
  use ExUnit.Case

  @moduletag :integration
  @moduletag :external
  @moduletag :slow

  setup do
    # Ensure Python + DSPy are installed
    case System.cmd("python3", ["-c", "import dspy"]) do
      {_, 0} -> :ok
      _ -> {:skip, "DSPy not installed"}
    end
  end

  test "actually introspects DSPy from Python" do
    # Override config to use REAL adapter
    Application.put_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitAdapter)

    # This will:
    # 1. Start real Snakepit worker
    # 2. Execute Python introspection script
    # 3. Return real DSPy schema
    {:ok, schema} = SnakeBridge.Discovery.discover("dspy")

    # Verify real Python data
    assert is_binary(schema["library_version"])
    assert schema["library_version"] =~ ~r/\d+\.\d+/
    assert Map.has_key?(schema["classes"], "Predict")
    assert Map.has_key?(schema["classes"], "ChainOfThought")
  end

  test "generates and executes real DSPy.Predict" do
    Application.put_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitAdapter)

    # Generate module from real schema
    {:ok, schema} = SnakeBridge.Discovery.discover("dspy")
    config = SnakeBridge.Discovery.schema_to_config(schema, python_module: "dspy")
    {:ok, [predictor_module | _]} = SnakeBridge.Generator.generate_all(config)

    # Actually call Python
    {:ok, instance} = predictor_module.create(%{signature: "question -> answer"})
    {:ok, result} = predictor_module.call(instance, %{question: "What is 2+2?"})

    # Verify real Python execution
    assert is_map(result)
    assert Map.has_key?(result, "answer")
  end
end
```

**Run separately**:
```bash
# Skip by default
mix test

# Run integration tests explicitly
mix test --only integration
```

---

## Mock vs Real Decision Matrix

| Component | Unit Tests | Integration Tests | Real Integration |
|-----------|------------|-------------------|------------------|
| **Config** | ✅ No mock | N/A | N/A |
| **TypeSystem** | ✅ No mock | N/A | N/A |
| **Schema.Differ** | ✅ No mock | N/A | N/A |
| **Cache** | ✅ Real ETS | ✅ Real ETS | ✅ Real ETS |
| **Generator** | ✅ No mock | ⚠️ Mock Runtime | ✅ Real Runtime |
| **Discovery** | ⚠️ Mock Snakepit | ⚠️ Mock Snakepit | ✅ Real Snakepit |
| **Runtime** | ⚠️ Mock Snakepit | ⚠️ Mock Snakepit | ✅ Real Snakepit |

**Key**:
- ✅ No mock = Pure Elixir testing
- ⚠️ Mock = Use adapter pattern
- ✅ Real = Actual external dependency

---

## Implementation Checklist

### Phase 1: Current (Mocked Snakepit)

- [x] Define `SnakeBridge.SnakepitBehaviour`
- [x] Create `SnakeBridge.SnakepitMock` (test/support)
- [x] Create `SnakeBridge.SnakepitAdapter` (lib/)
- [x] Configure adapter in config/test.exs
- [x] Update Runtime/Discovery to use adapter
- [ ] All unit tests pass with mock

### Phase 2: Integration Tests (Later)

- [ ] Create `test/integration/real_python_test.exs`
- [ ] Tag with `:integration`, `:external`, `:slow`
- [ ] Add Python environment checks (skip if missing)
- [ ] Document setup requirements (Python, DSPy, etc.)

### Phase 3: CI Configuration

```yaml
# .github/workflows/elixir.yaml

jobs:
  test-unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
      - run: mix deps.get
      - run: mix test  # Only unit tests (fast)

  test-integration:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      - run: pip install dspy-ai  # Install Python deps
      - run: mix deps.get
      - run: mix test --only integration  # Integration tests
```

---

## Benefits of This Strategy

### 1. **Fast Feedback Loop**

```bash
# Unit tests: <1 second
mix test test/unit

# No Python needed for development
# Just pure Elixir logic testing
```

### 2. **Reliable CI**

- Unit tests always pass (no external deps)
- Integration tests optional (separate job)
- No flaky tests from Python timeouts

### 3. **Clear Boundaries**

```
Pure Elixir ────┐
                │ (No Mocking)
Unit Tests ─────┘

Snakepit Boundary ────┐
                      │ (Mock via Adapter)
Integration Tests ────┘

Real Python ────┐
               │ (No Mocking)
E2E Tests ─────┘
```

### 4. **Easy Debugging**

```elixir
# Test fails? Check which layer:

# 1. Pure logic issue? → Fix the algorithm
test "type mapping is wrong" do
  assert Mapper.to_elixir_spec(type) == expected
end

# 2. Mock response wrong? → Fix the mock
test "discovery parsing fails" do
  # Mock returned unexpected format
end

# 3. Real integration broken? → Fix Python/Snakepit
@tag :integration
test "real Python fails" do
  # Actual DSPy issue
end
```

### 5. **TDD-Friendly**

```elixir
# Write test with mock
test "new feature works" do
  # Use mock response
  expect(Mock, :execute, fn -> {:ok, fake_data} end)
  assert MyModule.new_function() == expected
end

# Implement feature against mock
def new_function do
  # Implementation
end

# Later: Verify with real integration test
@tag :integration
test "new feature works with real Python" do
  assert MyModule.new_function() == real_expected
end
```

---

## Summary

### The Strategy

1. **Unit tests** (90% of tests): Pure Elixir, no mocks
2. **Integration tests** (9% of tests): Mocked Snakepit via adapter
3. **E2E tests** (1% of tests): Real Snakepit + Python, tagged

### The Adapter Pattern

```
┌─────────────────────────────────────────┐
│       SnakeBridge.Runtime               │
│                                         │
│   adapter = snakepit_adapter()         │
│   adapter.execute_in_session(...)      │
└──────────────┬──────────────────────────┘
               │
       ┌───────┴────────┐
       │                │
   Test Mode        Prod Mode
       │                │
       ▼                ▼
┌─────────────┐  ┌──────────────────┐
│ SnakepitMock│  │ SnakepitAdapter  │
│  (Mocked)   │  │  (Real Snakepit) │
└─────────────┘  └──────────────────┘
```

### Configuration

```elixir
# config/test.exs
config :snakebridge, snakepit_adapter: SnakeBridge.SnakepitMock

# config/dev.exs
config :snakebridge, snakepit_adapter: SnakeBridge.SnakepitAdapter

# config/runtime.exs (prod)
config :snakebridge, snakepit_adapter: SnakeBridge.SnakepitAdapter
```

### Running Tests

```bash
# Fast unit tests (mocked)
mix test                              # Default: excludes :integration

# With mocked integration
mix test test/integration             # Uses mock

# Real Python integration
mix test --only integration           # Requires Python + DSPy
mix test --only external

# Coverage
mix coveralls                         # Unit + mocked integration
mix coveralls --include integration   # All tests (needs Python)
```

---

## Next Steps

1. ✅ Create `SnakeBridge.SnakepitBehaviour`
2. ✅ Create `SnakeBridge.SnakepitMock` (test/support)
3. ✅ Create `SnakeBridge.SnakepitAdapter` (lib/)
4. ✅ Update `SnakeBridge.Runtime` to use adapter
5. ✅ Update `SnakeBridge.Discovery` to use adapter
6. ⬜ Make all unit tests pass with mock
7. ⬜ Add integration tests for later

**Status**: Strategy defined, ready to implement adapter pattern

---

**Conclusion**: We use **the adapter pattern** to cleanly separate mocked tests (fast, reliable) from real integration tests (slow, external). This gives us:

- Fast TDD cycle (unit tests)
- Confidence in integration (mocked integration tests)
- Production validation (real E2E tests)

**Best of all worlds!**
