# Implementation Prompt: Domain 4 - Dynamic Dispatch & Proxy

## Context

You are implementing dynamic dispatch for SnakeBridge to enable calling methods without pre-generated code. This is a **P1** domain.

## Required Reading

Before implementing, read these files in order:

### Critique Documents
1. `docs/20251229/critique/001_gpt52.md` - Section 8 (no-codegen escape hatch)
2. `docs/20251229/critique/002_g3p.md` - Sections A, 1 (compile-time wall, ghost module)

### Implementation Plan
3. `docs/20251229/implementation/00_master_plan.md` - Domain 4 overview

### Source Files (Elixir)
4. `lib/snakebridge/runtime.ex` - Existing call/call_method functions
5. `lib/snakebridge/ref.ex` - Reference structure
6. `lib/snakebridge/types/encoder.ex` - Type encoding
7. `lib/snakebridge/types/decoder.ex` - Type decoding

### Source Files (Python)
8. `priv/python/snakebridge_adapter.py` - Method call handlers (lines 764-779)
9. `priv/python/snakebridge_types.py` - Type encoding/decoding

### Test Files
10. `test/snakebridge/runtime_contract_test.exs` - Runtime contract tests

## Issues to Fix

### Issue 4.1: Dynamic Method Dispatch (P1)
**Problem**: When Python returns an object of an un-generated class, users can only call methods via verbose `Runtime.call_method/4`.
**Location**: No `SnakeBridge.Dynamic` module exists
**Fix**: Create `SnakeBridge.Dynamic` module with ergonomic API for calling methods on any Ref.

### Issue 4.2: No-Codegen Function Calls (P1)
**Problem**: Cannot call Python functions that weren't scanned during compilation.
**Location**: `lib/snakebridge/runtime.ex`
**Fix**: Add `call_dynamic/4` that accepts module path as string, bypassing generated wrappers.

### Issue 4.3: Ref Type Integration (P1)
**Problem**: Refs returned from Python aren't explicitly handled in encoder/decoder.
**Location**: `lib/snakebridge/types/decoder.ex`
**Fix**: Add explicit decoder clause for `__type__: "ref"` maps.

## TDD Implementation Steps

### Step 1: Write Tests First

Create `test/snakebridge/dynamic_test.exs`:
```elixir
defmodule SnakeBridge.DynamicTest do
  use ExUnit.Case, async: true

  describe "Dynamic.call/4" do
    test "calls method on ref" do
      ref = %{
        "__type__" => "ref",
        "__schema__" => 1,
        "id" => "test123",
        "session_id" => "default",
        "python_module" => "test",
        "library" => "test"
      }

      # Verify payload structure
      payload = SnakeBridge.Dynamic.build_call_payload(ref, :method_name, [1, 2])
      assert payload["call_type"] == "method"
      assert payload["method"] == "method_name"
      assert payload["instance"]["id"] == "test123"
    end

    test "validates ref structure" do
      invalid_ref = %{"id" => "123"}  # Missing required fields

      assert_raise ArgumentError, ~r/invalid ref/i, fn ->
        SnakeBridge.Dynamic.call(invalid_ref, :method, [])
      end
    end
  end

  describe "call_dynamic/4" do
    test "builds payload with string module path" do
      payload = SnakeBridge.Runtime.build_dynamic_payload(
        "numpy.linalg",
        "svd",
        [[1, 2], [3, 4]],
        full_matrices: false
      )

      assert payload["call_type"] == "dynamic"
      assert payload["module_path"] == "numpy.linalg"
      assert payload["function"] == "svd"
    end
  end
end
```

Create `test/snakebridge/ref_decoder_test.exs`:
```elixir
defmodule SnakeBridge.RefDecoderTest do
  use ExUnit.Case, async: true

  describe "ref decoding" do
    test "decodes ref type correctly" do
      ref_data = %{
        "__type__" => "ref",
        "__schema__" => 1,
        "id" => "abc123",
        "session_id" => "default",
        "python_module" => "numpy",
        "library" => "numpy"
      }

      result = SnakeBridge.Types.decode(ref_data)

      assert result["__type__"] == "ref"
      assert result["id"] == "abc123"
    end
  end
end
```

### Step 2: Run Tests (Expect Failures)
```bash
mix test test/snakebridge/dynamic_test.exs
mix test test/snakebridge/ref_decoder_test.exs
```

### Step 3: Implement Fixes

#### 3.1 Create SnakeBridge.Dynamic Module
File: `lib/snakebridge/dynamic.ex` (new file)

```elixir
defmodule SnakeBridge.Dynamic do
  @moduledoc """
  Dynamic dispatch for calling methods on Python objects without pre-generated code.

  Use this module when:
  - Python returns an object of a class you didn't generate bindings for
  - You need to call methods dynamically at runtime
  - You want a no-codegen escape hatch

  ## Examples

      # Call a method on any ref
      {:ok, result} = SnakeBridge.Dynamic.call(ref, :method_name, [arg1, arg2])

      # With keyword arguments
      {:ok, result} = SnakeBridge.Dynamic.call(ref, :method_name, [arg1], kwarg: value)

      # Get an attribute
      {:ok, value} = SnakeBridge.Dynamic.get_attr(ref, :attr_name)

      # Set an attribute
      :ok = SnakeBridge.Dynamic.set_attr(ref, :attr_name, new_value)
  """

  alias SnakeBridge.Runtime

  @type ref :: map()
  @type opts :: keyword()

  @doc """
  Calls a method on a Python object reference.

  ## Parameters

    * `ref` - A reference map with `__type__: "ref"`
    * `method` - Method name as atom or string
    * `args` - List of positional arguments
    * `opts` - Keyword arguments to pass to Python

  ## Returns

    * `{:ok, result}` on success
    * `{:error, reason}` on failure
  """
  @spec call(ref(), atom() | String.t(), list(), opts()) ::
    {:ok, term()} | {:error, Snakepit.Error.t()}
  def call(ref, method, args \\ [], opts \\ []) do
    validate_ref!(ref)
    Runtime.call_method(ref, method, args, opts)
  end

  @doc """
  Gets an attribute from a Python object reference.
  """
  @spec get_attr(ref(), atom() | String.t(), opts()) ::
    {:ok, term()} | {:error, Snakepit.Error.t()}
  def get_attr(ref, attr, opts \\ []) do
    validate_ref!(ref)
    Runtime.get_attr(ref, attr, opts)
  end

  @doc """
  Sets an attribute on a Python object reference.
  """
  @spec set_attr(ref(), atom() | String.t(), term(), opts()) ::
    {:ok, term()} | {:error, Snakepit.Error.t()}
  def set_attr(ref, attr, value, opts \\ []) do
    validate_ref!(ref)
    Runtime.set_attr(ref, attr, value, opts)
  end

  @doc """
  Checks if a value is a valid Python reference.
  """
  @spec is_ref?(term()) :: boolean()
  def is_ref?(%{"__type__" => "ref", "id" => _, "session_id" => _}), do: true
  def is_ref?(_), do: false

  @doc false
  def build_call_payload(ref, method, args) do
    %{
      "call_type" => "method",
      "instance" => ref,
      "method" => to_string(method),
      "args" => args
    }
  end

  defp validate_ref!(ref) do
    unless is_ref?(ref) do
      raise ArgumentError, """
      Invalid ref structure. Expected map with:
        - "__type__" => "ref"
        - "id" => <string>
        - "session_id" => <string>

      Got: #{inspect(ref)}
      """
    end
  end
end
```

#### 3.2 Add call_dynamic to Runtime
File: `lib/snakebridge/runtime.ex`

Add new function:
```elixir
@doc """
Calls any Python function dynamically without requiring generated bindings.

This is the "no-codegen escape hatch" for calling functions that weren't
scanned during compilation.

## Examples

    # Call a function
    SnakeBridge.Runtime.call_dynamic("numpy.linalg", "svd", [matrix])

    # With keyword arguments
    SnakeBridge.Runtime.call_dynamic("numpy.linalg", "svd", [matrix], full_matrices: false)

## Parameters

    * `module_path` - Python module path as string (e.g., "numpy.linalg")
    * `function` - Function name as string (e.g., "svd")
    * `args` - List of positional arguments
    * `opts` - Keyword arguments and runtime options

## Returns

    * `{:ok, result}` on success
    * `{:error, reason}` on failure
"""
@spec call_dynamic(String.t(), String.t(), list(), keyword()) ::
  {:ok, term()} | {:error, Snakepit.Error.t()}
def call_dynamic(module_path, function, args \\ [], opts \\ []) when is_binary(module_path) do
  {runtime_opts, kwargs} = normalize_args_opts([], opts)

  # Encode args at boundary
  encoded_args = Enum.map(args, &SnakeBridge.Types.encode/1)
  encoded_kwargs = encode_kwargs(kwargs)

  payload = protocol_payload()
    |> Map.put("call_type", "dynamic")
    |> Map.put("module_path", module_path)
    |> Map.put("function", to_string(function))
    |> Map.put("args", encoded_args)
    |> Map.put("kwargs", encoded_kwargs)

  metadata = %{
    library: :dynamic,
    function: String.to_atom(function),
    call_type: :dynamic,
    module_path: module_path
  }

  result = execute_with_telemetry(metadata, fn ->
    runtime_client().execute("snakebridge.call", payload, runtime_opts)
  end)

  # Decode result at boundary
  case result do
    {:ok, value} -> {:ok, SnakeBridge.Types.decode(value)}
    error -> error
  end
end

@doc false
def build_dynamic_payload(module_path, function, args, opts) do
  {_, kwargs} = normalize_args_opts([], opts)

  protocol_payload()
  |> Map.put("call_type", "dynamic")
  |> Map.put("module_path", module_path)
  |> Map.put("function", to_string(function))
  |> Map.put("args", args)
  |> Map.put("kwargs", Map.new(kwargs, fn {k, v} -> {to_string(k), v} end))
end
```

#### 3.3 Update Python Adapter for Dynamic Calls
File: `priv/python/snakebridge_adapter.py`

Add handler in `execute_tool`:
```python
if call_type == "dynamic":
    module_path = arguments.get("module_path")
    function_name = arguments.get("function")
    args = arguments.get("args", [])
    kwargs = arguments.get("kwargs", {})

    # Import module and get function
    module = _import_module(module_path)
    func = getattr(module, function_name)

    # Decode args
    decoded_args = [decode(arg) for arg in args]
    decoded_kwargs = {k: decode(v) for k, v in kwargs.items()}

    # Call function
    result = func(*decoded_args, **decoded_kwargs)

    # Encode result (auto-ref for unknown types)
    return encode_result(result, session_id, module_path, "dynamic")
```

#### 3.4 Add Ref Decoder
File: `lib/snakebridge/types/decoder.ex`

Add clause before catch-all:
```elixir
@doc """
Decodes a Python reference.
Refs are returned as-is, preserving the wire format for later use.
"""
def decode(%{"__type__" => "ref"} = ref) do
  # Validate required fields
  required = ["id", "session_id"]
  missing = Enum.filter(required, &(not Map.has_key?(ref, &1)))

  if missing != [] do
    raise ArgumentError, "Invalid ref: missing fields #{inspect(missing)}"
  end

  ref
end
```

### Step 4: Run Tests (Expect Pass)
```bash
mix test test/snakebridge/dynamic_test.exs
mix test test/snakebridge/ref_decoder_test.exs
mix test
```

### Step 5: Run Full Quality Checks
```bash
mix compile --warnings-as-errors
mix dialyzer
mix credo --strict
```

### Step 6: Update Examples

Create `examples/dynamic_dispatch_example/` to demonstrate:
- Calling methods on dynamically-returned objects
- Using `call_dynamic/4` for un-scanned functions
- Getting/setting attributes on refs
- Error handling for invalid refs

Update `examples/run_all.sh` with new example.

### Step 7: Update Documentation

Update `README.md`:
- Document `SnakeBridge.Dynamic` module
- Document `Runtime.call_dynamic/4`
- Explain when to use dynamic vs generated wrappers
- Add performance considerations

## Acceptance Criteria

- [ ] `Dynamic.call/4` works on any valid ref
- [ ] `call_dynamic/4` calls un-scanned Python functions
- [ ] Refs decoded correctly from Python responses
- [ ] Invalid refs raise clear ArgumentError
- [ ] Results properly encoded/decoded (including nested refs)
- [ ] Telemetry emitted for dynamic calls
- [ ] All existing tests pass
- [ ] New tests for this domain pass
- [ ] No dialyzer errors
- [ ] No credo warnings

## Dependencies

This domain depends on:
- Domain 1 (Type System) - auto-ref for unknown types
- Domain 3 (Class Resolution) - class method signatures

This domain enables:
- Domain 5 (Reference Lifecycle) - dynamic refs need lifecycle management
- Domain 6 (Python Idioms) - generators, context managers
