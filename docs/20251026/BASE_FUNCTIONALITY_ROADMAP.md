# SnakeBridge Base Functionality Roadmap

**Date**: 2025-10-26
**Status**: Post-TDD Success, Planning Next Steps
**Current**: 76/76 tests passing, all core modules complete
**Goal**: Prove the technology works with minimal viable examples

---

> Update (2025-12-23): This roadmap is historical. SnakeBridge is now manifest‑driven (JSON manifests + allowlist), Snakepit is 0.7.0, the Python adapter and serializers are implemented, and real‑Python tests pass. For current usage, see `README.md` and `docs/20251222/snakebridge-functionality/full_functionality.md`.

## Reality Check: What We Actually Have

### ✅ Working (Tested with Mocks)
- Complete Elixir layer (Config, Discovery, Generator, Runtime)
- Mix tasks (discover, validate, generate, clean)
- Public API (discover, generate, integrate)
- 76 tests, all passing

### ❌ Not Working (No Python Code)
- No Python adapter implementing `describe_library` tool
- No Python adapter implementing `call_python` tool
- Cannot actually execute Python code
- Cannot actually introspect Python libraries

### 🤔 The Gap
**Everything works in tests because SnakepitMock returns fake data.**
**To work for real, we need Python adapter code.**

---

## The Core Question: Adapter Complexity

### Hypothesis to Test
**Simple libraries** (numpy, requests) → Simple adapters (~50 lines)
**Complex libraries** (Demo, LangChain) → Complex adapters (~500+ lines?)

**We need data points to know if AI automation is worth it.**

### Experiments to Run

1. **Build minimal adapter** for simple Python library (requests, json)
   - Measure: lines of code, edge cases, time to build
   - Result: Baseline complexity

2. **Build adapter** for medium complexity (numpy, pandas)
   - Measure: same metrics
   - Result: Does complexity scale linearly?

3. **Build adapter** for Demo (complex)
   - Measure: same metrics
   - Result: Is AI automation justified?

**After 3 examples, we'll KNOW if we need AI or if manual is fine.**

---

## Immediate Next Steps: Prove It Works

### Phase 1: Minimal Viable Adapter (Week 1)

**Goal**: Get ONE Python library working end-to-end

**Target**: Python's built-in `json` module (simplest possible)

#### Step 1.1: Create Generic Python Adapter
**File**: `priv/python/snakebridge_adapter.py`

```python
"""
Generic SnakeBridge adapter for dynamic Python integration.
Supports ANY Python library via dynamic imports.
"""

from snakepit_bridge.base_adapter_threaded import ThreadSafeAdapter, tool
import importlib
import inspect
import uuid

class SnakeBridgeAdapter(ThreadSafeAdapter):
    def __init__(self):
        super().__init__()
        self.instances = {}  # {instance_id: python_object}

    @tool(description="Introspect Python module structure")
    def describe_library(self, module_path: str, discovery_depth: int = 2) -> dict:
        """
        Introspect Python module and return schema.

        Returns:
        {
            "library_version": "x.y.z",
            "classes": {<class_name>: <descriptor>},
            "functions": {<func_name>: <descriptor>}
        }
        """
        try:
            module = importlib.import_module(module_path)
            return self._introspect_module(module, discovery_depth)
        except Exception as e:
            return {"success": False, "error": str(e)}

    @tool(description="Call Python function or method dynamically")
    def call_python(self, module_path: str, function_name: str,
                   args: list = None, kwargs: dict = None) -> dict:
        """
        Dynamically execute Python code.

        If function_name == "__init__":
            - Create instance
            - Store in self.instances
            - Return instance_id

        Otherwise:
            - If module_path starts with "instance:": Call method on stored instance
            - Otherwise: Call module-level function
        """
        args = args or []
        kwargs = kwargs or {}

        try:
            if function_name == "__init__":
                return self._create_instance(module_path, args, kwargs)
            elif module_path.startswith("instance:"):
                return self._call_instance_method(module_path, function_name, args, kwargs)
            else:
                return self._call_module_function(module_path, function_name, args, kwargs)
        except Exception as e:
            return {"success": False, "error": str(e)}

    def _introspect_module(self, module, depth):
        # Use inspect module to discover classes, functions, methods
        # Return schema in SnakeBridge format
        ...

    def _create_instance(self, module_path, args, kwargs):
        # Import class, instantiate, store, return instance_id
        ...

    def _call_instance_method(self, instance_ref, method_name, args, kwargs):
        # Retrieve instance, call method, return result
        ...
```

**Estimated**: 150-200 lines for complete generic adapter
**Time**: 4-6 hours to write and test

---

#### Step 1.2: Register Adapter with Snakepit
**File**: `config/runtime.exs` or startup code

```elixir
# Ensure Snakepit uses our adapter
config :snakepit,
  adapter: SnakeBridgeAdapter,  # Python class
  python_path: Path.join(:code.priv_dir(:snakebridge), "python")
```

**Time**: 1 hour to configure

---

#### Step 1.3: Test with `json` Module
**Why `json`**: Built-in, no installation, simple API

```elixir
# Should work after Step 1.1-1.2
{:ok, schema} = SnakeBridge.discover("json")
# Returns: %{"functions" => %{"dumps" => %{...}, "loads" => %{...}}}

config = SnakeBridge.Discovery.schema_to_config(schema, python_module: "json")
{:ok, [JsonModule]} = SnakeBridge.generate(config)

# Call Python's json.dumps
{:ok, result} = JsonModule.dumps(%{test: "data"})
# Should return: "{\"test\": \"data\"}"
```

**Test**: Create `test/integration/real_python_json_test.exs`
**Time**: 2 hours

**Total Phase 1**: 8 hours
**Deliverable**: ONE Python library (json) working end-to-end

---

### Phase 2: Simple Library Examples (Week 2)

**Goal**: Prove adapter works for different complexity levels

#### Example 2.1: `requests` Library
**Complexity**: Low (just HTTP functions)
**API Surface**: ~10 functions (get, post, put, delete, etc.)

```elixir
{:ok, modules} = SnakeBridge.integrate("requests")
[RequestsModule] = modules
{:ok, response} = RequestsModule.get(%{url: "https://api.github.com"})
```

**Adapter changes needed**: Probably none (generic adapter should work)
**Test file**: `test/integration/real_python_requests_test.exs`
**Time**: 2 hours

---

#### Example 2.2: `numpy` Library
**Complexity**: Medium (classes + functions, complex types)
**API Surface**: ~100s of functions, ndarray class

```elixir
{:ok, modules} = SnakeBridge.integrate("numpy")
# Might generate: [Numpy.Ndarray, NumpyModule]

{:ok, array_ref} = Numpy.Ndarray.create(%{data: [1, 2, 3, 4]})
{:ok, result} = Numpy.Ndarray.mean(array_ref, %{})
# result => %{"value" => 2.5}
```

**Adapter changes needed**: Type conversion (Python arrays ↔ Elixir lists)
**Complexity increase**: ~50 lines for type handling
**Time**: 4 hours

---

#### Example 2.3: Demo in DSPex Project
**Complexity**: High (complex API, stateful, callbacks)
**Location**: ~/p/g/n/DSPex

**Why separate project**:
- Demo is domain-specific (prompt programming)
- Needs custom business logic on top of SnakeBridge
- Good separation of concerns

**What SnakeBridge provides to DSPex**:
```elixir
# In DSPex project:
# mix.exs
defp deps do
  [
    {:snakebridge, "~> 0.1.0"},
    {:snakepit, "~> 0.6"}
  ]
end

# Usage in DSPex
defmodule DSPex.Predictor do
  # Use SnakeBridge to get base Demo integration
  {:ok, modules} = SnakeBridge.integrate("demo")
  [demo_predict | _] = modules

  # DSPex adds domain logic on top
  def predict_with_context(prompt, context) do
    # Business logic here
    demo_predict.call(...)
  end
end
```

**Adapter changes needed**:
- Streaming support
- Callback handling
- Complex state management
**Complexity increase**: ~200 lines
**Time**: 8 hours

---

### Phase 3: Measure & Decide (End of Week 2)

After building 3 examples, we'll have data:

**Metrics to collect**:
| Library | API Surface | Adapter LOC | Edge Cases | Time to Build | Works? |
|---------|-------------|-------------|------------|---------------|--------|
| json    | ~10 funcs   | ? lines     | ?          | ? hours       | ?      |
| requests| ~10 funcs   | ? lines     | ?          | ? hours       | ?      |
| numpy   | ~100s funcs | ? lines     | ?          | ? hours       | ?      |
| Demo    | Complex     | ? lines     | ?          | ? hours       | ?      |

**Decision Point**:
- If adapter LOC stays ~50-100 → Manual is fine, skip AI
- If adapter LOC grows to 500+ → AI automation justified
- If edge cases explode → AI helps with refinement

---

## The Actual Implementation Steps

### Step 1: Generic Python Adapter (CRITICAL)

**File**: `priv/python/snakebridge_adapter.py`

**What to implement**:
```python
class SnakeBridgeAdapter(ThreadSafeAdapter):
    # Core tools
    def describe_library(self, module_path, depth)
    def call_python(self, module_path, function_name, args, kwargs)

    # Helpers
    def _introspect_module(self, module, depth)
    def _create_instance(self, module_path, args, kwargs)
    def _call_instance_method(self, instance_ref, method, args, kwargs)
    def _call_module_function(self, module_path, function, args, kwargs)
    def _convert_types(self, obj)  # Python → JSON-safe
```

**Key decisions**:
- How to store instances? (dict with UUIDs)
- How to reference instances? (session_id + instance_id)
- How to handle Python exceptions? (catch, return error dict)
- How deep to introspect? (respect depth param)

**Time estimate**: 6-8 hours for production-quality code

---

### Step 2: Update Runtime to Use Generic Tool

**Current**: Calls `"call_demo"` (specific)
**Update to**: Call `"call_python"` (generic)

**File**: `lib/snakebridge/runtime.ex`
```elixir
# Line 35: Change from "call_demo" to "call_python"
case adapter.execute_in_session(session_id, "call_python", %{
  "module_path" => python_path,
  "function_name" => "__init__",
  ...
})
```

**Time**: 15 minutes + tests

---

### Step 3: Setup Mix Task

**File**: `lib/mix/tasks/snakebridge/setup/python.ex`

```elixir
defmodule Mix.Tasks.Snakebridge.Setup.Python do
  @moduledoc """
  Setup Python environment for SnakeBridge.

  ## What it does:
  1. Creates Python virtual environment (.venv)
  2. Installs Snakepit Python dependencies (grpcio, protobuf)
  3. Installs SnakeBridge adapter
  4. Optionally installs packages from config
  """

  use Mix.Task

  def run(args) do
    # Create venv
    # pip install grpcio protobuf
    # pip install -e priv/python  (installs snakebridge_adapter)
    # pip install packages from config/snakebridge/python_packages.exs
  end
end
```

**Time**: 2-3 hours

---

### Step 4: Python Package Config

**File**: `config/snakebridge/python_packages.exs`

```elixir
# Python packages to install for SnakeBridge adapters

[
  # Minimal test - no external deps
  %{
    package_name: nil,  # built-in
    import_name: "json",
    purpose: :smoke_test,
    install: false
  },

  # Simple HTTP library
  %{
    package_name: "requests",
    import_name: "requests",
    version: "2.31.0",
    purpose: :example,
    install: true
  },

  # Demo for DSPex project
  %{
    package_name: "demo-ai",
    import_name: "demo",
    version: "2.5.0",  # Latest as of Oct 2025
    source: "https://github.com/stanfordnlp/demo",
    install: true,
    dependencies: ["openai>=1.0.0", "anthropic>=0.3.0"],
    notes: "Used by DSPex project for prompt programming"
  }
]
```

**Time**: 30 minutes

---

### Step 5: Integration Tests (Real Python)

**File**: `test/integration/real_python/json_test.exs`

```elixir
defmodule SnakeBridge.Integration.RealPython.JsonTest do
  use ExUnit.Case

  @moduletag :integration
  @moduletag :external
  @moduletag :slow
  @moduletag :real_python

  setup do
    # Switch to real adapter
    Application.put_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitAdapter)

    # Ensure Python + Snakepit running
    unless Code.ensure_loaded?(Snakepit) do
      {:skip, "Snakepit not available"}
    end
  end

  test "discovers json module schema" do
    {:ok, schema} = SnakeBridge.discover("json")

    assert is_map(schema)
    assert schema["library_version"]
    assert Map.has_key?(schema["functions"], "dumps")
    assert Map.has_key?(schema["functions"], "loads")
  end

  test "generates and calls json.dumps" do
    {:ok, modules} = SnakeBridge.integrate("json")
    [json_module | _] = modules

    # Call json.dumps({"test": "data"})
    {:ok, result} = json_module.dumps(%{test: "data"})

    # Should return JSON string
    assert is_binary(result) or is_map(result)
  end

  test "roundtrip: dumps then loads" do
    {:ok, modules} = SnakeBridge.integrate("json")
    [json_module | _] = modules

    data = %{hello: "world", number: 42}

    {:ok, json_string} = json_module.dumps(data)
    {:ok, parsed} = json_module.loads(%{s: json_string})

    assert parsed == data
  end
end
```

**Time**: 2 hours

---

## Simplified Roadmap: Prove First, Automate Later

### Week 1: Get ONE Library Working

**Deliverables**:
- [ ] Generic Python adapter (150-200 lines)
- [ ] `mix snakebridge.setup.python` task
- [ ] Python package config schema
- [ ] Integration test with `json` module
- [ ] Documentation of what we learned

**Questions answered**:
- Does the generic adapter approach work?
- What's the complexity baseline?
- What edge cases appear immediately?

**Success metric**: Can call `json.dumps` from Elixir via SnakeBridge ✅

---

### Week 2: Scale to 2-3 More Libraries

**Libraries to try** (in order of complexity):
1. `requests` (simple HTTP)
2. `math` (built-in, pure functions)
3. `numpy` (classes, arrays, types)

**Deliverables**:
- [ ] Adapter works with all 3 (or document why not)
- [ ] Update adapter based on lessons learned
- [ ] Measure: LOC, time, edge cases per library
- [ ] Integration tests for each

**Questions answered**:
- Does complexity scale linearly with API surface?
- Are there common patterns we can abstract?
- Do we need library-specific adapters or is generic enough?

**Success metric**: 3 different library types working ✅

---

### Week 3: Demo Integration in DSPex Project

**Location**: ~/p/g/n/DSPex (separate project)

**Deliverables**:
- [ ] DSPex depends on SnakeBridge
- [ ] Basic Demo example works (Predict)
- [ ] Document complexity vs simple libraries
- [ ] Identify Demo-specific challenges

**Questions answered**:
- Is Demo too complex for generic adapter?
- Do we need custom adapter per complex library?
- Is AI automation worth building?

**Success metric**: Can run Demo.Predict from DSPex via SnakeBridge ✅

---

### Week 4: Decision Point & Documentation

**Based on data from Weeks 1-3, decide**:

**Option A: Manual is Fine**
- If adapters stay <200 LOC
- If patterns are reusable
- If edge cases are manageable
→ Build 10-20 adapters manually
→ Document patterns
→ Ship v0.2.0

**Option B: AI Automation Justified**
- If adapters grow to 500+ LOC
- If too many edge cases
- If each library is unique
→ Build control plane (from AI_AGENT doc)
→ Integrate gemini_ex + codex_sdk
→ Ship v0.3.0 with AI generation

**Deliverables**:
- [ ] Data-driven decision document
- [ ] Complexity analysis
- [ ] Updated roadmap based on findings

---

## Detailed First Steps (Next Session)

### Immediate Priority Order

#### 1. Create Python Adapter (BLOCKING EVERYTHING)
**File**: `priv/python/snakebridge_adapter.py`
**Status**: Critical path
**Blocks**: All real Python execution
**Approach**:
- Start minimal (just `describe_library` for `json` module)
- Expand to `call_python` for functions only (no classes yet)
- Add instance management later

**Minimal Version 1** (~50 lines):
```python
@tool
def describe_library(self, module_path: str) -> dict:
    mod = importlib.import_module(module_path)
    return {
        "library_version": getattr(mod, "__version__", "unknown"),
        "functions": self._get_functions(mod),
        "classes": {}  # Start simple
    }

def _get_functions(self, module):
    funcs = {}
    for name, obj in inspect.getmembers(module, inspect.isfunction):
        funcs[name] = {
            "name": name,
            "python_path": f"{module.__name__}.{name}",
            "docstring": inspect.getdoc(obj) or ""
        }
    return funcs
```

---

#### 2. Update Runtime Tool Names
**File**: `lib/snakebridge/runtime.ex`
**Change**: `"call_demo"` → `"call_python"`
**File**: `test/support/snakepit_mock.ex`
**Change**: Add `"call_python"` handler (or rename `call_demo`)
**Time**: 30 min

---

#### 3. Setup Task
**File**: `lib/mix/tasks/snakebridge/setup/python.ex`
**Minimum**:
```elixir
def run(_args) do
  Mix.shell().info("Setting up Python environment...")

  # Check Python available
  {_, 0} = System.cmd("python3", ["--version"])

  # Install Snakepit Python deps
  {_, 0} = System.cmd("pip3", ["install", "grpcio", "protobuf"])

  Mix.shell().info("✓ Python environment ready")
end
```
**Time**: 1 hour

---

#### 4. First Real Test
**File**: `test/integration/real_python/json_smoke_test.exs`
```elixir
@tag :real_python
test "can discover and call json.dumps" do
  # Use real Snakepit
  Application.put_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitAdapter)

  # Discover
  {:ok, schema} = SnakeBridge.discover("json")
  assert Map.has_key?(schema["functions"], "dumps")

  # Generate
  config = SnakeBridge.Discovery.schema_to_config(schema, python_module: "json")
  {:ok, modules} = SnakeBridge.generate(config)

  # Execute
  [json_mod] = modules
  {:ok, result} = json_mod.dumps(%{test: "data"})

  # Verify
  assert is_binary(result)
  assert result =~ "test"
end
```
**Time**: 2 hours

---

## What About AI Automation?

### Current Stance: **Build it LATER, after we have data**

**Why not now**:
1. Don't know if it's needed yet
2. Generic adapter might work for 80% of cases
3. Building control plane is 3-4 weeks
4. Better to prove base functionality first

**When to revisit**:
- After 3-5 library examples
- If adapter complexity explodes
- If manual process is painful
- If Sonnet 5.0 arrives (better at code gen)

**What to build now for future AI**:
- Clean separation (adapter files, tests, configs)
- Validation harness (we can reuse for AI later)
- Template structure (useful even for manual)
- Package config schema (same for manual or AI)

---

## Success Criteria

### Milestone 1: Proof of Concept (1 week)
- [ ] Python adapter exists and runs
- [ ] Can call `json.dumps` from Elixir
- [ ] Tests pass with real Python (not mocks)
- [ ] Document what works and what doesn't

### Milestone 2: Multiple Libraries (2 weeks)
- [ ] 3+ different libraries working
- [ ] Complexity data collected
- [ ] Common patterns identified
- [ ] Edge cases documented

### Milestone 3: Decision Made (3 weeks)
- [ ] Data-driven choice: manual vs AI automation
- [ ] Roadmap updated based on findings
- [ ] Next phase clearly defined

---

## Risk Mitigation

### What if generic adapter doesn't work?

**Fallback**: Library-specific adapters (still simpler than AI automation)
```python
# priv/python/adapters/demo_adapter.py (Demo-specific)
# priv/python/adapters/numpy_adapter.py (numpy-specific)
```

### What if Python integration is too hard?

**Fallback**: Reduce scope to function-only (no classes)
- Still useful for many libraries
- Simpler adapter code
- Can add classes later

### What if Snakepit integration is broken?

**Fallback**: Direct stdio communication (simpler than gRPC)
- Fall back to stdio adapter in Snakepit
- Less performant but more reliable

---

## The Path Forward

### Next Immediate Actions (Next Session)

1. **Create minimal Python adapter** (describe_library only)
   - Just enough to discover `json` module
   - ~30-50 lines
   - Test manually first

2. **Test with real Snakepit**
   - Start Snakepit with our adapter
   - Call `SnakeBridge.discover("json")` for real
   - See what breaks

3. **Fix issues** as they come up
   - Type conversions
   - Error handling
   - Schema format mismatches

4. **Document learnings**
   - What worked
   - What didn't
   - Complexity assessment

**After that**: Decide if we continue with more examples or pivot to AI automation.

---

## Summary

**Vision**: AI-generated adapters for scale (documented in AI_AGENT doc)
**Reality**: Need to prove base functionality first
**Approach**: Build 1-3 examples manually, measure complexity, then decide
**Next**: Create minimal Python adapter and get json.dumps working

**AI automation is a rabbit hole** - agree to defer until we have data showing it's needed.

**Focus now**: Make ONE Python library work end-to-end. Everything else is speculation until that happens.

---

**Status**: Ready to build `priv/python/snakebridge_adapter.py` and prove the technology works.
