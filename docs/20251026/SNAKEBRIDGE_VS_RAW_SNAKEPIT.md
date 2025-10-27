# SnakeBridge vs Raw Snakepit: The Value Proposition

**Question**: Why use SnakeBridge when Snakepit already provides Python integration?

**Answer**: SnakeBridge eliminates **thousands of lines of boilerplate** through automatic code generation.

---

## Scenario: Integrating NumPy

NumPy has:
- **626 functions** (mean, std, dot, fft, etc.)
- **72 classes** (ndarray, matrix, etc.)
- Complex type system
- Extensive API surface

### Path A: Raw Snakepit (Manual)

#### Step 1: Write Python Adapter (~200 lines per library)

**File**: `priv/python/my_numpy_adapter.py`

```python
from snakepit_bridge.base_adapter_threaded import ThreadSafeAdapter, tool
import numpy as np

class MyNumpyAdapter(ThreadSafeAdapter):
    """Custom adapter for NumPy - must write manually"""

    @tool(description="Calculate mean")
    def numpy_mean(self, data):
        return {"result": float(np.mean(data))}

    @tool(description="Calculate standard deviation")
    def numpy_std(self, data):
        return {"result": float(np.std(data))}

    @tool(description="Dot product")
    def numpy_dot(self, a, b):
        result = np.dot(a, b)
        return {"result": result.tolist() if hasattr(result, 'tolist') else float(result)}

    @tool(description="Create array")
    def numpy_array(self, data):
        arr = np.array(data)
        arr_id = str(uuid.uuid4())
        self.arrays[arr_id] = arr
        return {"array_id": arr_id, "shape": arr.shape}

    # ... repeat for 622 more functions 😱
    # Plus handle classes, type conversions, error cases
```

**Effort**:
- 5-10 lines per function
- × 626 functions
- **= 3,000-6,000 lines of Python**

---

#### Step 2: Write Elixir Wrapper (~200 lines per library)

**File**: `lib/my_app/numpy.ex`

```elixir
defmodule MyApp.Numpy do
  @moduledoc "NumPy integration - manually wrapped"

  @doc "Calculate mean of a list"
  @spec mean([number()]) :: {:ok, float()} | {:error, term()}
  def mean(data) when is_list(data) do
    case Snakepit.execute("numpy_mean", %{data: data}) do
      {:ok, %{"result" => result}} -> {:ok, result}
      {:error, _} = error -> error
    end
  end

  @doc "Calculate standard deviation"
  @spec std([number()]) :: {:ok, float()} | {:error, term()}
  def std(data) when is_list(data) do
    case Snakepit.execute("numpy_std", %{data: data}) do
      {:ok, %{"result" => result}} -> {:ok, result}
      {:error, _} = error -> error
    end
  end

  @doc "Dot product of two arrays"
  @spec dot([number()], [number()]) :: {:ok, number() | [number()]} | {:error, term()}
  def dot(a, b) when is_list(a) and is_list(b) do
    case Snakepit.execute("numpy_dot", %{a: a, b: b}) do
      {:ok, %{"result" => result}} -> {:ok, result}
      {:error, _} = error -> error
    end
  end

  # ... repeat for 622 more functions 😱
  # Plus type specs, docs, guards, error handling
end
```

**Effort**:
- 4-8 lines per function
- × 626 functions
- **= 2,500-5,000 lines of Elixir**

---

#### Step 3: Write Tests (~100 lines per library)

```elixir
defmodule MyApp.NumpyTest do
  use ExUnit.Case

  test "mean calculation" do
    assert {:ok, 3.0} = MyApp.Numpy.mean([1, 2, 3, 4, 5])
  end

  # ... 50+ more tests
end
```

---

#### Total Manual Effort:
- **Python adapter**: 3,000-6,000 lines
- **Elixir wrapper**: 2,500-5,000 lines
- **Tests**: 100-500 lines
- **Type specs**: Included above
- **Documentation**: Included above
- **Total**: **~10,000 lines of code**
- **Time**: 40-80 hours
- **Maintenance**: Ongoing (NumPy updates = rewrite)

---

### Path B: SnakeBridge (Automatic)

#### Step 1: Integrate (ONE command)

```elixir
{:ok, modules} = SnakeBridge.integrate("numpy")
```

**Generated automatically**:
- ✅ Python adapter (SnakeBridgeAdapter works for ALL libraries)
- ✅ Elixir wrapper modules (626 functions)
- ✅ Type specs (inferred from Python)
- ✅ Documentation (from docstrings)
- ✅ Error handling (built-in)

#### Step 2: Use It

```elixir
# All 626 NumPy functions available immediately
Numpy.mean([1, 2, 3, 4, 5])
Numpy.std([1, 2, 3, 4, 5])
Numpy.dot([1, 2], [3, 4])
# ... 623 more functions, all available
```

#### Total Automatic Effort:
- **Python adapter**: 0 lines (generic adapter)
- **Elixir wrapper**: 0 lines (auto-generated)
- **Tests**: 0 lines initially (can add later)
- **Type specs**: AUTO
- **Documentation**: AUTO
- **Total**: **0 lines of code**
- **Time**: 10 seconds
- **Maintenance**: Zero (re-run discover on updates)

---

## The Difference

| Task | Raw Snakepit | SnakeBridge | Savings |
|------|--------------|-------------|---------|
| **Python adapter** | 3,000-6,000 lines | 0 lines | 100% |
| **Elixir wrapper** | 2,500-5,000 lines | 0 lines | 100% |
| **Type specs** | Manual | Auto-generated | 100% |
| **Documentation** | Manual | Auto from docstrings | 100% |
| **Time to integrate** | 40-80 hours | 10 seconds | 99.99% |
| **Maintenance** | Ongoing | Re-run discover | 95% |
| **Error prone** | High (manual code) | Low (generated) | N/A |

---

## Real World Impact

### Integrating 10 Python Libraries

**Without SnakeBridge**:
- 10 libraries × 200 functions average × 10 lines = **20,000 lines**
- 10 libraries × 40 hours = **400 hours of work**
- Ongoing maintenance for all 10

**With SnakeBridge**:
```bash
for lib in numpy pandas scipy requests matplotlib; do
  elixir -e "SnakeBridge.integrate(\"$lib\")"
done
# Done in 60 seconds
```

---

## What SnakeBridge Actually Does

### 1. Generic Python Adapter (Write Once)

**SnakeBridgeAdapter** (300 lines) works with **ANY** library:
- `describe_library` - introspects any Python module
- `call_python` - executes any Python code
- Dynamic imports, instance management, type conversion

**This replaces**: Writing custom adapter per library (N × 200 lines)

### 2. Automatic Code Generation

**Generator** reads Python introspection and emits:
```elixir
# For each Python function, generates:
@doc "Docstring from Python"
@spec function_name(args...) :: return_type
def function_name(args) do
  SnakeBridge.Runtime.call_method(...)  # Routes to Python
end
```

**This replaces**: Writing Elixir wrapper per function (N × 5 lines)

### 3. Type System Mapping

Automatically converts:
- Python `int` → Elixir `integer()`
- Python `List[float]` → Elixir `[float()]`
- Python `Dict[str, Any]` → Elixir `%{String.t() => term()}`
- Python classes → Elixir opaque types

**This replaces**: Manual type specs per function

### 4. Discovery System

Uses Python's `inspect` module to discover:
- All functions and their signatures
- All classes and their methods
- Docstrings
- Type hints (when available)
- Parameter defaults

**This replaces**: Reading docs and manually transcribing

---

## The Key Insight

**Snakepit provides**: Transport layer (gRPC, pooling, sessions)
**SnakeBridge adds**: Automatic glue code generation

**Snakepit** = Database driver (low-level)
**SnakeBridge** = ORM (high-level, automatic)

Without SnakeBridge, you're writing SQL by hand.
With SnakeBridge, you're using Ecto.

---

## Example Comparison

### Task: Calculate mean of a list

#### Raw Snakepit Way:

```python
# 1. Write Python adapter tool
@tool
def calculate_mean(self, data):
    import numpy as np
    return {"result": float(np.mean(data))}
```

```elixir
# 2. Write Elixir wrapper
def mean(data) do
  case Snakepit.execute("calculate_mean", %{data: data}) do
    {:ok, %{"result" => r}} -> {:ok, r}
    error -> error
  end
end
```

**Total**: ~15 lines of code per function

#### SnakeBridge Way:

```elixir
# 1. Discover
{:ok, modules} = SnakeBridge.integrate("numpy")

# 2. Use
Numpy.mean([1, 2, 3, 4, 5])
```

**Total**: 0 lines of code (auto-generated from introspection)

---

## Why This Matters

### Scenario: You need 20 NumPy functions

**Raw Snakepit**:
- Write 20 Python @tool methods (200 lines)
- Write 20 Elixir wrappers (160 lines)
- Write 20 type specs (40 lines)
- Write 20 doc comments (60 lines)
- **Total: 460 lines**
- **Time: 3-4 hours**

**SnakeBridge**:
```elixir
SnakeBridge.integrate("numpy")
# All 626 functions available
# Use the 20 you need
# Total: 0 lines
# Time: 10 seconds
```

### Scenario: NumPy releases v2.0 with API changes

**Raw Snakepit**:
- Review changelog
- Update Python adapter (1-2 hours)
- Update Elixir wrapper (1-2 hours)
- Update tests (30 min)
- **Total: 3-4 hours**

**SnakeBridge**:
```bash
mix snakebridge.discover numpy --force  # Re-discover
# Auto-updates to new API
# Time: 10 seconds
```

---

## The Bottom Line

**SnakeBridge is a code generator that eliminates boilerplate.**

For ONE library, the savings are nice.
For TEN libraries, the savings are massive.
For ANY library in Python's ecosystem, it's transformative.

**You're not writing glue code. SnakeBridge writes it for you.**

That's the value.
