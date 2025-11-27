# PHASE 1B: SnakeBridge Architecture Analysis Report

**Date:** November 2025
**Purpose:** Deep architectural analysis to identify opportunities for reusability and pluggability

---

## Executive Summary

SnakeBridge is a sophisticated metaprogramming framework that bridges Elixir and Python through a six-layer architecture. The codebase demonstrates strong separation of concerns but reveals several opportunities for increased reusability and pluggability:

**Key Findings:**
1. **Strong Foundation**: Clean behavior-based abstractions exist (SnakepitBehaviour, IntrospectorBehaviour) enabling testing and swapping implementations
2. **Extension Points Exist**: Adapter pattern is partially implemented but not fully exploited across all layers
3. **Duplication Risk**: Code generation patterns repeat across classes/functions/modules without abstraction
4. **Type System Inflexibility**: TypeSystem.Mapper is hardcoded for primitive types; extending with new types (torch.Tensor, numpy.ndarray, pandas.DataFrame) requires direct modification
5. **Configuration Rigidity**: Config system lacks true plugin architecture for specialized adapters beyond the catalog
6. **Runtime Coupling**: Snakepit coupling is minimal but could be further abstracted for truly pluggable backends

**Recommended Priority**: Phase 1B improvements should focus on:
1. Creating an Adapter Registry pattern
2. Extracting Type Mapper as a pluggable strategy
3. Unifying code generation patterns with a generator strategy pattern
4. Making Python Adapter introspection pluggable

---

## 1. Current Extension Points

### 1.1 Existing Abstractions (Behaviors)

**Location**: `lib/snakebridge/snakepit_behaviour.ex`

The project already uses Elixir behaviors as extension points:

```elixir
@callback execute_in_session(
  session_id :: String.t(),
  tool_name :: String.t(),
  args :: map()
) :: {:ok, map()} | {:error, term()}
```

**Usage Pattern**:
- Production: `SnakeBridge.SnakepitAdapter` implements real Snakepit delegation
- Testing: `SnakeBridge.SnakepitMock` provides canned responses
- Configured via: `Application.get_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitAdapter)`

**Assessment**: ✅ **Well-designed** - Clean two-implementation pattern. However, the behavior is minimal and only covers execution, not higher-level concerns like discovery or type mapping.

### 1.2 Discovery Adapter (Partial Pattern)

**Location**: `lib/snakebridge/discovery/introspector.ex` and `lib/snakebridge/discovery/introspector_behaviour.ex`

```elixir
# Behavior definition
@callback discover(module_path :: String.t(), opts :: keyword()) ::
            {:ok, map()} | {:error, term()}
```

**Assessment**: ⚠️ **Partially Pluggable** - The behavior exists but there's only one implementation plus implicit mocking via mock responses. Could be cleaner.

### 1.3 Code Generation: Where Extensions Are Needed

**Location**: `lib/snakebridge/generator.ex` (330 LOC)

The generator has two parallel code generation paths:
1. **Class modules**: `generate_module/2`
2. **Function modules**: `generate_function_module/2`

**Problem**: Both paths duplicate similar logic for module naming, docstrings, hooks, and quote blocks.

**Assessment**: ❌ **Not Pluggable** - No abstraction for code generation strategies.

### 1.4 Type System: Hardcoded Mappings

**Location**: `lib/snakebridge/type_system/mapper.ex` (133 LOC)

```elixir
def to_elixir_spec(%{kind: "primitive", primitive_type: "int"}), do: quote(do: integer())
def to_elixir_spec(%{kind: "primitive", primitive_type: "str"}), do: quote(do: String.t())
# ... 12 more primitives ...
```

**Current State**:
- Handles primitives (int, str, float, bool, bytes, none, any)
- Handles collections (list, dict, union)
- Handles classes
- Missing: numpy.ndarray, pandas.DataFrame, torch.Tensor, PIL.Image, etc.

**Assessment**: ❌ **Not Extensible** - No hook for custom type mappers. Every new type requires modifying core module.

---

## 2. Code Duplication Analysis

### 2.1 Dual Code Generation Paths

**Files**: `lib/snakebridge/generator.ex`

```
generate_module/2           ~50 LOC
generate_function_module/2  ~30 LOC
                            --------
DUPLICATED PATTERNS:        ~25 LOC (75%)
```

**Duplicated Patterns**:

| Pattern | Class Path | Function Path |
|---------|-----------|---------------|
| Module name derivation | ✅ | ✅ |
| Docstring generation | ✅ | ✅ |
| Python path assignment | ✅ | ✅ |
| Config assignment | ✅ | ✅ |
| Hook generation | ✅ | ✅ |
| Session ID generation | ✅ | ✅ |

**Cost**:
- Adding a feature to both paths requires changes in 2 places
- Risk of divergence and bugs
- Testing burden doubles

### 2.2 Method/Function Generation Loop Duplication

**Location**: `lib/snakebridge/generator.ex`

```elixir
# generate_methods/1 - 31 LOC
defp generate_methods(methods) when is_list(methods) do
  Enum.map(methods, fn method -> ... end)
end

# generate_functions/2 - 38 LOC (VERY SIMILAR)
defp generate_functions(functions, module_python_path) when is_list(functions) do
  Enum.map(functions, fn function -> ... end)
end
```

**Duplication**: ~60% of code is identical. Only difference:
- Methods use `instance_ref` + `call_method`
- Functions use direct `call_function`

### 2.3 Mock Response Generation Duplication

**Location**: `test/support/snakepit_mock.ex` (255 LOC)

**Problem**: To add a new test library, copy-paste 30 LOC and modify 3-4 fields.

---

## 3. Configuration System Analysis

### 3.1 Current Flexibility

**Location**: `lib/snakebridge/config.ex` (260 LOC)

The Config struct has good breadth:

```elixir
defstruct python_module: nil,
          version: nil,
          description: nil,
          introspection: %{...},
          classes: [],
          functions: [],
          bidirectional_tools: %{...},
          grpc: %{...},
          caching: %{...},
          telemetry: %{...},
          mixins: [],
          extends: nil,
          timeout: nil,
          compilation_mode: :auto
```

### 3.2 What's Missing for True Pluggability

**Issue 1: Adapter Selection is Hardcoded**

```elixir
# Current approach in catalog.ex
def adapter_config(library_name) do
  case get(library_name) do
    nil -> {:error, :not_in_catalog}
    entry -> {:ok, build_config(entry)}
  end
end
```

**Problem**: To use a new adapter:
1. Modify `Catalog.@catalog` list (hardcoded)
2. Restart application
3. No way to dynamically discover or register adapters

**Recommended**: Create an Adapter Registry:
```elixir
defmodule SnakeBridge.Adapter.Registry do
  @callback name() :: atom()
  @callback python_module() :: String.t()
  @callback python_class() :: String.t()
  @callback capabilities() :: keyword()

  def get_adapter(name), do: lookup(name)
  def register(adapter_module), do: store(adapter_module)
end
```

**Issue 2: Type Mappers Can't Be Swapped**

Current: Fixed `SnakeBridge.TypeSystem.Mapper` module
Needed: Configurable type mapping strategy per-library

**Issue 3: Generator Hooks Are Limited**

Current hooks:
- `@before_compile` (compile-time mode)
- `@on_load` (runtime mode)
- No hooks for: pre-generation, optimization, post-generation

---

## 4. Type System Extensibility

### 4.1 Current Architecture

**Location**: `lib/snakebridge/type_system/mapper.ex` (133 LOC)

Two-way mapping:
- **to_elixir_spec**: Python type descriptor → Elixir typespec AST
- **infer_python_type**: Elixir value → Python type identifier

**Current Support**:
```
✅ Primitives: int, str, float, bool, bytes, none, any (7 types)
✅ Collections: list, dict, union (3 types)
✅ Classes: python_class_to_elixir_module (1 type)
❌ NumPy types: ndarray, dtype, generic
❌ PyTorch types: Tensor, Device, dtype
❌ Pandas types: DataFrame, Series, Index
❌ PIL types: Image
❌ Custom user types
```

### 4.2 Recommended Refactoring

**Create Type Mapper Behavior**:

```elixir
defmodule SnakeBridge.TypeSystem.MapperBehaviour do
  @callback to_elixir_spec(descriptor :: map()) :: Macro.t() | nil
  @callback infer_python_type(value :: term()) :: {:ok, map()} | :not_handled
  @callback priority() :: integer()  # 0=lowest, 100=highest
end

defmodule SnakeBridge.TypeSystem.MapperChain do
  def to_elixir_spec(descriptor, mappers \\ default_mappers()) do
    mappers
    |> Enum.sort_by(&apply(&1, :priority, []), :desc)
    |> Enum.find_map(fn mapper ->
      case apply(mapper, :to_elixir_spec, [descriptor]) do
        nil -> nil
        result -> result
      end
    end)
    || quote(do: term())
  end
end

# Usage in config:
%SnakeBridge.Config{
  type_mappers: [
    SnakeBridge.TypeSystem.PrimitiveMapper,
    SnakeBridge.TypeSystem.CollectionMapper,
    MyApp.TorchMapper,  # Custom mapper, no core modification
  ]
}
```

---

## 5. Generator Architecture

### 5.1 Current Flow

```
Config → generate_all/1
  ├─ For each class:
  │  ├─ generate_module/2      → AST
  │  ├─ compile_and_load/1     → Runtime compiled
  │  └─ {:ok, module}
  │
  └─ For each function:
     ├─ group_functions_by_module/1
     ├─ generate_function_module/2 → AST
     ├─ compile_and_load/1         → Runtime compiled
     └─ {:ok, module}
```

### 5.2 Missing Abstractions

**Issue 1: No Generator Strategy Pattern**

To add Rust FFI generation, you'd need:
1. Copy generate_module/2 → generate_rust_ffi/2
2. Rewrite all quote blocks for Rust syntax
3. Add new compile step
4. Modify generate_all/1 to handle new type

**Desired: Strategy Pattern**

```elixir
defmodule SnakeBridge.Generator.Strategy do
  @callback generate(descriptor :: map(), config :: Config.t()) :: {:ok, term()} | {:error, term()}
  @callback compile_and_load(output :: term()) :: {:ok, module()} | {:error, term()}
  @callback output_format() :: :elixir | :rust | :python | :custom
end

defmodule SnakeBridge.Generator.ElixirStrategy do
  @behaviour SnakeBridge.Generator.Strategy

  def generate(descriptor, config), do: {:ok, generate_module(descriptor, config)}
  def compile_and_load(ast), do: # Current code
end
```

---

## 6. Runtime Execution Patterns

### 6.1 Current Patterns in Runtime.ex

**File**: `lib/snakebridge/runtime.ex` (157 LOC)

Three execution patterns are implemented:

| Pattern | Entry Point | Python Tool |
|---------|-------------|-------------|
| Instance Creation | `create_instance/4` | `call_python` with `__init__` |
| Method Calls | `call_method/4` | `call_python` with `instance:<id>` |
| Module Functions | `call_function/4` | `call_python` with module path |
| Streaming | `execute_stream/5` | Snakepit streaming |

### 6.2 Abstraction Opportunity: Execution Plan

All patterns follow a similar flow:
1. Extract/generate module_path
2. Prepare arguments (normalize_args)
3. Dispatch to adapter
4. Unwrap response
5. Return result

**Recommended: Execution Plan Pattern**

```elixir
defmodule SnakeBridge.Runtime.ExecutionPlan do
  defstruct [:session_id, :tool_name, :arguments, :opts, :response_handler]

  def execute(%__MODULE__{} = plan) do
    adapter = SnakeBridge.Runtime.snakepit_adapter()
    case adapter.execute_in_session(plan.session_id, plan.tool_name, plan.arguments, plan.opts) do
      {:ok, response} -> {:ok, plan.response_handler.(response)}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

---

## 7. Testing Architecture

### 7.1 Current Test Structure

```
test/
├── support/
│   ├── snakepit_mock.ex      (255 LOC)
│   ├── test_fixtures.ex      (210 LOC)
│   └── test_behaviours.ex    (32 LOC)
├── unit/
├── integration/
├── property/
└── adapters/
```

### 7.2 Mock Implementation Quality

**Strengths**:
- Covers main use cases (describe_library, call_python)
- Responses are realistic
- No network/Python dependency

**Weaknesses**:
- New library support requires copy-paste
- Hardcoded response logic can't be customized
- No way to simulate Python errors
- No time-based behavior simulation

### 7.3 Needed: Adapter Testing Framework

```elixir
defmodule SnakeBridge.Testing.AdapterTestHelper do
  def test_adapter(adapter_module, expectations) do
    # Verify adapter implements behaviour
    # Test initialization
    # Test tool execution
    # Test error handling
  end
end
```

---

## 8. Python Adapter Deep Dive

### 8.1 Generic Adapter Design (adapter.py - 382 LOC)

**Location**: `priv/python/snakebridge_adapter/adapter.py`

**Architecture**:
```python
class SnakeBridgeAdapter(ThreadSafeAdapter):
    def execute_tool(self, tool_name, arguments, context):
        """Dispatch to appropriate tool"""

    def describe_library(self, module_path, discovery_depth):
        """Introspect module"""

    def call_python(self, module_path, function_name, args, kwargs):
        """Execute code"""
```

**Three Tool Entry Points**:

1. **describe_library**: Introspects a module using `inspect`
2. **call_python**: Dynamic execution (instances, methods, functions)
3. **execute_tool**: Dispatch layer

### 8.2 Specialization Pattern (genai adapter - 237 LOC)

**Location**: `priv/python/adapters/genai/adapter.py`

**Problems**:
1. **Code Duplication**: Creates a new SnakeBridgeAdapter to handle discovery/execution
2. **No Composition**: Can't compose multiple specializations
3. **Initialization Risk**: Lazy initialization can fail in event loop

### 8.3 Recommended: Adapter Composition Chain

```python
class Handler:
    """Base handler interface"""
    def can_handle(self, tool_name: str) -> bool:
        raise NotImplementedError

    def execute(self, arguments: dict, context) -> dict:
        raise NotImplementedError

class SnakeBridgeAdapter(ThreadSafeAdapter):
    def __init__(self):
        self.handlers = [DiscoveryHandler(), ExecutionHandler()]

    def execute_tool(self, tool_name: str, arguments: dict, context):
        handler = next((h for h in self.handlers if h.can_handle(tool_name)), None)
        if handler:
            return handler.execute(arguments, context)
        return {"success": False, "error": f"Unknown tool: {tool_name}"}

# Specialized adapters just add handlers
class GenAIAdapter(SnakeBridgeAdapter):
    def __init__(self):
        super().__init__()
        self.handlers.insert(0, TextGenHandler())
```

### 8.4 Instance Storage Concerns

**Current approach**: In-memory dict
```python
self.instances = {}  # {instance_id: python_object}
```

**Issues**:
1. **No Cleanup**: Instances accumulate in memory
2. **No TTL**: Long-lived instances cause memory leaks
3. **No Eviction**: No policy for handling out-of-memory
4. **Session-Unaware**: Instances not tied to sessions

**Recommended**: Instance Manager with TTL and eviction policies

---

## 9. Foundation Improvements Roadmap

### Phase 1B-1 (Immediate - 1-2 weeks)

**Priority 1: Adapter Registry**
```elixir
lib/snakebridge/adapter_registry.ex
- Interface for registering adapters
- Discovery by name/library
- Configuration-driven selection
```

**Priority 2: Unify Code Generation**
```elixir
lib/snakebridge/generator/base.ex        # Common logic
lib/snakebridge/generator/descriptor.ex  # Descriptor handling
lib/snakebridge/generator/quote_helper.ex # AST helpers
```

**Priority 3: Type Mapper Registry**
```elixir
lib/snakebridge/type_system/mapper_behaviour.ex
lib/snakebridge/type_system/mapper_chain.ex
lib/snakebridge/type_system/primitive_mapper.ex
lib/snakebridge/type_system/collection_mapper.ex
lib/snakebridge/type_system/class_mapper.ex
```

### Phase 1B-2 (Short-term - 2-4 weeks)

**Priority 4: Generator Strategy Pattern**
```elixir
lib/snakebridge/generator/strategy.ex
lib/snakebridge/generator/strategies/elixir.ex
lib/snakebridge/generator/strategies/docs.ex
```

**Priority 5: Execution Plan Pattern**
```elixir
lib/snakebridge/runtime/execution_plan.ex
lib/snakebridge/runtime/plan_builder.ex
```

**Priority 6: Python Adapter Handler Chain**
```python
priv/python/snakebridge_adapter/handler.py
priv/python/snakebridge_adapter/handlers/discovery.py
priv/python/snakebridge_adapter/handlers/execution.py
```

### Phase 1B-3 (Medium-term - 1-2 months)

**Priority 7: Test Helper Framework**
```elixir
lib/snakebridge/testing/adapter_test_helper.ex
lib/snakebridge/testing/fixture_builder.ex
lib/snakebridge/testing/mock_registry.ex
```

**Priority 8: Configuration DSL Enhancements**
```elixir
%SnakeBridge.Config{
  type_mappers: [...],
  generator_strategy: MyStrategy,
  runtime_executor: MyExecutor
}
```

---

## 10. Concrete Refactoring Recommendations

### 10.1 Extract Generator Base (High Impact)

**Before** (generator.ex - 330 LOC, duplicated):
```elixir
defmodule SnakeBridge.Generator do
  def generate_module(descriptor, config) do ... end
  def generate_function_module(descriptor, config) do ... end
end
```

**After** (modularized):
```elixir
defmodule SnakeBridge.Generator.DescriptorProcessor do
  def normalize_descriptor(descriptor), do: ...
end

defmodule SnakeBridge.Generator.ASTBuilder do
  def build_module(name, python_path, docstring, config, do_block), do: ...
end
```

**Impact**: Reduces generator.ex from 330 → 200 LOC, enables reuse.

### 10.2 Pluggable Type Mappers (High Impact)

**Before**: Fixed mapper module with 20+ clauses
**After**: Chain of small, composable mappers

**Impact**:
- Core mapper.ex shrinks from 133 → 20 LOC
- No core modifications to add new types
- Testable in isolation

### 10.3 Execution Plan Pattern (Medium Impact)

**Before**: Duplicated case/with blocks in runtime.ex
**After**: Declarative ExecutionPlan struct

**Impact**:
- Runtime.ex becomes more readable
- Foundation for batch execution, retries, circuit breakers

### 10.4 Python Adapter Handler Chain (High Impact)

**Before**: Code duplication between generic and specialized adapters
**After**: Composable handler chain

**Impact**:
- No code duplication
- Easy to test each handler in isolation
- New specializations just add handlers

---

## Summary of Findings

### Strengths
- ✅ Clean behavior-based abstractions (SnakepitBehaviour, IntrospectorBehaviour)
- ✅ Good test coverage with mocking strategy
- ✅ Configuration system is flexible (mixins, extends, composition)
- ✅ AST-based code generation is type-safe
- ✅ Runtime layer properly abstracts Snakepit

### Critical Gaps
- ❌ Code duplication in generator (class vs function modules)
- ❌ Type system is hardcoded (no extensibility for new types)
- ❌ No pluggable adapter registry
- ❌ Generator strategy pattern missing
- ❌ Python adapter has duplication (generic + specializations)

### Recommended Immediate Actions
1. **Extract Type Mapper Chain** - Enable custom types without core modifications
2. **Create Adapter Registry** - Allow dynamic adapter discovery
3. **Unify Code Generation** - Remove duplication between class/function generators
4. **Add Execution Plans** - Improve testability and extensibility of Runtime
5. **Python Handler Chain** - Remove duplication between adapters

---

*This analysis provides a foundation for making SnakeBridge significantly more extensible and reusable.*
