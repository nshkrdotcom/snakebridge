# Implementation Prompt: Domain 3 - Class & Module Resolution

## Context

You are implementing automatic class vs submodule disambiguation for SnakeBridge. This is a **P0 blocking** domain.

## Required Reading

Before implementing, read these files in order:

### Critique Documents
1. `docs/20251229/critique/001_gpt52.md` - Sections 2, 6, 7 (class support, module attributes, name sanitization)
2. `docs/20251229/critique/002_g3p.md` - Section A (compile-time wall)

### Implementation Plan
3. `docs/20251229/implementation/00_master_plan.md` - Domain 3 overview

### Source Files (Elixir)
4. `lib/mix/tasks/compile/snakebridge.ex` - python_module_for_elixir function (lines 231-240)
5. `lib/snakebridge/generator.ex` - Class generation (lines 219-259)
6. `lib/snakebridge/manifest.ex` - Class tracking in manifest
7. `lib/snakebridge/introspector.ex` - Class introspection (lines 258-302)
8. `lib/snakebridge/runtime.ex` - get_attr/set_attr functions (lines 106-144)

### Source Files (Python)
9. `priv/python/introspect.py` - inspect.isclass detection
10. `priv/python/snakebridge_adapter.py` - Class instantiation handling

### Test Files
11. `test/snakebridge/generator_test.exs` - Existing generator tests

## Issues to Fix

### Issue 3.1: Class vs Submodule Disambiguation (P0)
**Problem**: `Lib.Foo.bar()` always treated as submodule `lib.foo`, but `Foo` might be a class attribute of `lib`.
**Location**: `lib/mix/tasks/compile/snakebridge.ex` lines 231-240
**Fix**: Use introspection to detect if path component is a class or submodule. Try class attribute first, fall back to submodule.

### Issue 3.2: Module Attributes/Constants (P0)
**Problem**: Cannot access module-level constants like `math.pi`, `numpy.nan`, `torch.float32`.
**Locations**:
- `lib/snakebridge/runtime.ex` - has instance get_attr but no module attribute API
- `lib/snakebridge/introspector.ex` - doesn't capture module-level non-callable attributes
**Fix**: Add `get_module_attr/3` to Runtime. Extend introspection to capture module constants.

### Issue 3.3: Arity/Presence Model for Classes (P0)
**Problem**: Related to Domain 2 but affects class method detection.
**Location**: `lib/snakebridge/manifest.ex`
**Fix**: Apply same arity range matching to class methods.

### Issue 3.4: Method Name Sanitization (P1)
**Problem**: Method names like `class`, `__init__` need special handling.
**Location**: `lib/snakebridge/generator.ex` render_method
**Fix**: Apply function name sanitization to methods, store Python name mapping.

## TDD Implementation Steps

### Step 1: Write Tests First

Create `test/snakebridge/class_resolution_test.exs`:
```elixir
defmodule SnakeBridge.ClassResolutionTest do
  use ExUnit.Case, async: true

  describe "class vs submodule disambiguation" do
    test "detects class attribute on parent module" do
      # Mock introspection result
      result = SnakeBridge.Introspector.introspect_attribute(:numpy, "ndarray")
      assert result.is_class == true
    end

    test "falls back to submodule when not a class" do
      result = SnakeBridge.Introspector.introspect_attribute(:os, "path")
      assert result.is_class == false
      assert result.is_module == true
    end

    test "resolve_class_or_submodule returns correct type" do
      library = %{python_name: "numpy", module_name: Numpy}

      result = SnakeBridge.ModuleResolver.resolve_class_or_submodule(library, Numpy.NDArray)
      assert result == {:class, "ndarray", "numpy"}
    end
  end
end
```

Create `test/snakebridge/module_attr_test.exs`:
```elixir
defmodule SnakeBridge.ModuleAttrTest do
  use ExUnit.Case, async: true

  describe "module attribute access" do
    test "get_module_attr retrieves constant" do
      # Requires Python runtime for integration test
      # For unit test, verify payload structure
      payload = SnakeBridge.Runtime.build_module_attr_payload(Math, :pi)
      assert payload["call_type"] == "module_attr"
      assert payload["module"] == "math"
      assert payload["attr"] == "pi"
    end
  end
end
```

Create `test/snakebridge/method_sanitization_test.exs`:
```elixir
defmodule SnakeBridge.MethodSanitizationTest do
  use ExUnit.Case, async: true

  describe "method name sanitization" do
    test "sanitizes reserved word methods" do
      {elixir_name, python_name} = SnakeBridge.Generator.sanitize_method_name("class")
      assert elixir_name == "py_class"
      assert python_name == "class"
    end

    test "__init__ becomes new" do
      {elixir_name, python_name} = SnakeBridge.Generator.sanitize_method_name("__init__")
      assert elixir_name == "new"
      assert python_name == "__init__"
    end
  end
end
```

### Step 2: Run Tests (Expect Failures)
```bash
mix test test/snakebridge/class_resolution_test.exs
mix test test/snakebridge/module_attr_test.exs
mix test test/snakebridge/method_sanitization_test.exs
```

### Step 3: Implement Fixes

#### 3.1 Create Module Resolver
File: `lib/snakebridge/module_resolver.ex` (new file)

```elixir
defmodule SnakeBridge.ModuleResolver do
  @moduledoc """
  Resolves ambiguous module paths to class attributes or submodules.
  """

  alias SnakeBridge.Introspector

  @doc """
  Determines if a path component is a class or submodule.

  Returns:
    - {:class, class_name, parent_module} if it's a class attribute
    - {:submodule, module_path} if it's a submodule
    - {:error, reason} if resolution fails
  """
  @spec resolve_class_or_submodule(map(), module()) ::
    {:class, String.t(), String.t()} | {:submodule, String.t()} | {:error, term()}
  def resolve_class_or_submodule(library, elixir_module) do
    module_parts = Module.split(elixir_module)
    library_parts = Module.split(library.module_name)
    extra_parts = Enum.drop(module_parts, length(library_parts))

    case extra_parts do
      [] ->
        {:submodule, library.python_name}

      [class_candidate | rest] ->
        parent_module = library.python_name
        attr_name = Macro.underscore(class_candidate)

        case introspect_attribute_type(parent_module, attr_name) do
          {:ok, :class} ->
            {:class, attr_name, parent_module}

          {:ok, :module} ->
            {:submodule, "#{parent_module}.#{attr_name}"}

          {:error, _} ->
            # Fall back to submodule assumption
            full_path = [library.python_name | Enum.map(extra_parts, &Macro.underscore/1)]
            {:submodule, Enum.join(full_path, ".")}
        end
    end
  end

  defp introspect_attribute_type(module_path, attr_name) do
    case Introspector.introspect_attribute(module_path, attr_name) do
      {:ok, %{is_class: true}} -> {:ok, :class}
      {:ok, %{is_module: true}} -> {:ok, :module}
      {:ok, _} -> {:ok, :other}
      error -> error
    end
  end
end
```

#### 3.2 Extend Introspector for Attribute Checking
File: `lib/snakebridge/introspector.ex`

Add new function:
```elixir
@doc """
Introspects a single attribute on a module to determine its type.
"""
@spec introspect_attribute(String.t(), String.t(), keyword()) ::
  {:ok, map()} | {:error, term()}
def introspect_attribute(module_path, attr_name, opts \\ []) do
  script = attribute_introspection_script()
  args = [module_path, attr_name]

  case execute_python_script(script, args, opts) do
    {:ok, result} -> {:ok, Jason.decode!(result)}
    error -> error
  end
end

defp attribute_introspection_script do
  ~S"""
  import importlib
  import inspect
  import json
  import sys

  module_path = sys.argv[1]
  attr_name = sys.argv[2]

  try:
      module = importlib.import_module(module_path)
      attr = getattr(module, attr_name, None)

      if attr is None:
          result = {"exists": False}
      else:
          result = {
              "exists": True,
              "is_class": inspect.isclass(attr),
              "is_module": inspect.ismodule(attr),
              "is_function": inspect.isfunction(attr) or inspect.isbuiltin(attr),
              "type_name": type(attr).__name__
          }

      print(json.dumps(result))
  except Exception as e:
      print(json.dumps({"error": str(e)}))
  """
end
```

#### 3.3 Add Module Attribute Runtime Function
File: `lib/snakebridge/runtime.ex`

Add new public function:
```elixir
@doc """
Retrieves a module-level attribute (constant, class, etc.).

## Examples

    SnakeBridge.Runtime.get_module_attr(Math, :pi)
    {:ok, 3.141592653589793}

    SnakeBridge.Runtime.get_module_attr(Numpy, :nan)
    {:ok, NaN}
"""
@spec get_module_attr(module(), atom() | String.t(), opts()) ::
  {:ok, term()} | {:error, Snakepit.Error.t()}
def get_module_attr(module, attr, opts \\ []) do
  {runtime_opts, _} = normalize_args_opts([], opts)

  python_module = module.__snakebridge_python_module__()
  attr_str = to_string(attr)

  payload = protocol_payload()
    |> Map.put("call_type", "module_attr")
    |> Map.put("module", python_module)
    |> Map.put("attr", attr_str)

  metadata = %{
    library: module,
    function: :get_module_attr,
    call_type: :module_attr,
    attr: attr_str
  }

  execute_with_telemetry(metadata, fn ->
    runtime_client().execute("snakebridge.call", payload, runtime_opts)
  end)
  |> apply_error_mode(opts)
end

# Helper for building payload (used in tests)
@doc false
def build_module_attr_payload(module, attr) do
  python_module = module.__snakebridge_python_module__()

  protocol_payload()
  |> Map.put("call_type", "module_attr")
  |> Map.put("module", python_module)
  |> Map.put("attr", to_string(attr))
end
```

#### 3.4 Update Python Adapter for Module Attributes
File: `priv/python/snakebridge_adapter.py`

Add handler in `execute_tool`:
```python
if call_type == "module_attr":
    module_path = arguments.get("module")
    attr_name = arguments.get("attr")

    module = _import_module(module_path)
    attr_value = getattr(module, attr_name)

    return encode(attr_value)
```

#### 3.5 Generate Module Constant Accessors
File: `lib/snakebridge/generator.ex`

Add function for rendering module attributes:
```elixir
defp render_module_attributes(attrs, library) when is_list(attrs) do
  attrs
  |> Enum.map(fn attr ->
    name = attr["name"]
    type_hint = attr["type_hint"] || "term()"
    doc = attr["doc"] || "Module constant: #{name}"

    """
    @doc \"\"\"
    #{doc}
    \"\"\"
    @spec #{name}() :: {:ok, #{type_hint}} | {:error, Snakepit.Error.t()}
    def #{name}() do
      SnakeBridge.Runtime.get_module_attr(__MODULE__, :#{name})
    end
    """
  end)
  |> Enum.join("\n")
end
```

#### 3.6 Method Name Sanitization
File: `lib/snakebridge/generator.ex`

Add/update function:
```elixir
@dunder_mappings %{
  "__init__" => "new",
  "__str__" => "to_string",
  "__repr__" => "inspect",
  "__len__" => "length",
  "__getitem__" => "get",
  "__setitem__" => "put",
  "__contains__" => "member?"
}

defp sanitize_method_name(python_name) when is_binary(python_name) do
  cond do
    # Handle special dunder mappings
    Map.has_key?(@dunder_mappings, python_name) ->
      {Map.get(@dunder_mappings, python_name), python_name}

    # Skip other dunder methods
    String.starts_with?(python_name, "__") and String.ends_with?(python_name, "__") ->
      nil  # Skip, not exposed

    # Reserved words
    python_name in @reserved_words ->
      {"py_#{python_name}", python_name}

    # Normal case
    true ->
      sanitized = python_name
        |> Macro.underscore()
        |> String.replace(~r/[^a-z0-9_?!]/, "_")

      {sanitized, python_name}
  end
end
```

### Step 4: Run Tests (Expect Pass)
```bash
mix test test/snakebridge/class_resolution_test.exs
mix test test/snakebridge/module_attr_test.exs
mix test test/snakebridge/method_sanitization_test.exs
mix test
```

### Step 5: Run Full Quality Checks
```bash
mix compile --warnings-as-errors
mix dialyzer
mix credo --strict
```

### Step 6: Update Examples

Create `examples/class_resolution_example/` to demonstrate:
- Automatic class detection (numpy.ndarray as class)
- Module constant access (math.pi, numpy.nan)
- Method name mapping (new vs __init__)

Update `examples/run_all.sh` with new example.

### Step 7: Update Documentation

Update `README.md`:
- Document automatic class vs submodule detection
- Document module constant access
- Document method name mappings

## Acceptance Criteria

- [ ] Classes are auto-detected via introspection without manual `include`
- [ ] Module constants accessible via `get_module_attr/3`
- [ ] Submodule fallback works when class detection fails
- [ ] Method names sanitized and mapped correctly
- [ ] `__init__` maps to `new/N` in generated code
- [ ] All existing tests pass
- [ ] New tests for this domain pass
- [ ] No dialyzer errors
- [ ] No credo warnings

## Dependencies

This domain depends on:
- Domain 1 (Type System) - type marshalling for attribute values
- Domain 2 (Signature Model) - method arity handling

This domain enables:
- Domain 4 (Dynamic Dispatch) - dynamic method resolution
- Domain 7 (Protocol Integration) - dunder method mapping
