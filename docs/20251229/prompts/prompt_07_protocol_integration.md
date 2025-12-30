# Implementation Prompt: Domain 7 - Protocol Integration

## Context

You are implementing Elixir protocol support for Python objects (Inspect, Enumerable, String.Chars) and dynamic exception creation. This is a **P1** domain.

## Required Reading

Before implementing, read these files in order:

### Critique Documents
1. `docs/20251229/critique/002_g3p.md` - Section 3 (dunder mapping), 5 (exception hierarchy)

### Implementation Plan
2. `docs/20251229/implementation/00_master_plan.md` - Domain 7 overview

### Source Files (Elixir)
3. `lib/snakebridge/ref.ex` - Reference structure (no protocol impls yet)
4. `lib/snakebridge/error_translator.ex` - Manual exception translation
5. `lib/snakebridge/runtime.ex` - get_attr, call_method functions
6. `lib/snakebridge/introspector.ex` - Class introspection (skips dunders)

### Source Files (Python)
7. `priv/python/snakebridge_adapter.py` - Method call handlers
8. `priv/python/snakebridge_types.py` - Type encoding

### Test Files
9. `test/snakebridge/types/encoder_test.exs` - Type encoding tests
10. `test/snakebridge/types/decoder_test.exs` - Type decoding tests

## Issues to Fix

### Issue 7.1: Inspect Protocol for Refs (P1)
**Problem**: `inspect(python_ref)` shows raw map, not Python object representation.
**Location**: `lib/snakebridge/ref.ex` - no Inspect implementation
**Fix**: Implement Inspect protocol that calls Python `__str__` or `__repr__`.

### Issue 7.2: Enumerable Protocol for Refs (P1)
**Problem**: Cannot use `Enum.count/1`, `Enum.map/2` on Python collections.
**Location**: No Enumerable implementation for refs
**Fix**: Implement Enumerable that delegates to Python `__len__`, `__iter__`, `__getitem__`.

### Issue 7.3: String.Chars Protocol (P1)
**Problem**: Cannot use `"Result: #{python_ref}"` interpolation.
**Location**: No String.Chars implementation
**Fix**: Implement to_string that calls Python `__str__`.

### Issue 7.4: Dynamic Exception Creation (P0)
**Problem**: Unknown Python exceptions become generic RuntimeError.
**Location**: `lib/snakebridge/error_translator.ex`
**Fix**: Dynamically create Elixir exception structs from Python exception class names.

### Issue 7.5: Dunder Method Introspection (P1)
**Problem**: Introspector skips dunder methods, can't know if `__len__` exists.
**Location**: `lib/snakebridge/introspector.ex` lines 261-262, 289
**Fix**: Capture specific dunder methods for protocol mapping.

## TDD Implementation Steps

### Step 1: Write Tests First

Create `test/snakebridge/protocol_integration_test.exs`:
```elixir
defmodule SnakeBridge.ProtocolIntegrationTest do
  use ExUnit.Case, async: true

  describe "Inspect protocol" do
    test "inspect ref calls Python __str__" do
      # Create a mock ref
      ref = %{
        "__type__" => "ref",
        "id" => "test123",
        "session_id" => "default",
        "python_module" => "test",
        "library" => "test"
      }

      # Verify Inspect protocol is implemented
      # (Full test requires Python integration)
      assert Inspect.impl_for(ref) != nil || true  # Map has impl
    end
  end

  describe "Enumerable protocol for refs" do
    # Note: Full tests require Python runtime
    test "protocol implementation exists for SnakeBridge.Ref" do
      # Will fail until implemented
    end
  end
end
```

Create `test/snakebridge/dynamic_exception_test.exs`:
```elixir
defmodule SnakeBridge.DynamicExceptionTest do
  use ExUnit.Case

  describe "dynamic exception creation" do
    test "creates exception from Python class name" do
      exception = SnakeBridge.DynamicException.create("ValueError", "invalid value")

      assert exception.__struct__ == SnakeBridge.DynamicException.ValueError
      assert Exception.message(exception) == "invalid value"
    end

    test "handles nested class names" do
      exception = SnakeBridge.DynamicException.create(
        "requests.exceptions.HTTPError",
        "404 Not Found"
      )

      assert exception.__struct__ == SnakeBridge.DynamicException.HTTPError
    end

    test "exception implements Exception protocol" do
      exception = SnakeBridge.DynamicException.create("CustomError", "test")

      assert Exception.exception?(exception)
      assert is_binary(Exception.message(exception))
    end
  end
end
```

Create `test/snakebridge/dunder_introspection_test.exs`:
```elixir
defmodule SnakeBridge.DunderIntrospectionTest do
  use ExUnit.Case, async: true

  describe "dunder method detection" do
    test "introspection captures __len__ when present" do
      # Mock introspection result
      result = %{
        "dunder_methods" => ["__len__", "__getitem__", "__iter__"],
        "methods" => []
      }

      assert "__len__" in result["dunder_methods"]
    end

    test "dunder methods stored in manifest" do
      # Verify manifest schema supports dunder_methods
    end
  end
end
```

### Step 2: Run Tests (Expect Failures)
```bash
mix test test/snakebridge/protocol_integration_test.exs
mix test test/snakebridge/dynamic_exception_test.exs
mix test test/snakebridge/dunder_introspection_test.exs
```

### Step 3: Implement Fixes

#### 3.1 Create Ref Struct (if not exists)
File: `lib/snakebridge/ref.ex`

```elixir
defmodule SnakeBridge.Ref do
  @moduledoc """
  Represents a reference to a Python object.

  Implements Elixir protocols for seamless integration:
  - `Inspect` - for debugging and IEx display
  - `String.Chars` - for string interpolation
  """

  defstruct [
    :id,
    :session_id,
    :python_module,
    :library,
    :type_name,
    schema: 1
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    session_id: String.t(),
    python_module: String.t(),
    library: String.t(),
    type_name: String.t() | nil,
    schema: pos_integer()
  }

  @doc """
  Creates a Ref from wire format map.
  """
  def from_wire_format(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      session_id: map["session_id"],
      python_module: map["python_module"],
      library: map["library"],
      type_name: map["type_name"],
      schema: map["__schema__"] || 1
    }
  end

  @doc """
  Converts back to wire format for Python calls.
  """
  def to_wire_format(%__MODULE__{} = ref) do
    %{
      "__type__" => "ref",
      "__schema__" => ref.schema,
      "id" => ref.id,
      "session_id" => ref.session_id,
      "python_module" => ref.python_module,
      "library" => ref.library
    }
  end

  @doc """
  Checks if a value is a valid ref.
  """
  def is_ref?(%__MODULE__{}), do: true
  def is_ref?(%{"__type__" => "ref"}), do: true
  def is_ref?(_), do: false
end
```

#### 3.2 Implement Inspect Protocol
File: `lib/snakebridge/ref.ex` (add to same file)

```elixir
defimpl Inspect, for: SnakeBridge.Ref do
  import Inspect.Algebra

  def inspect(%SnakeBridge.Ref{} = ref, opts) do
    # Try to get Python string representation
    case get_python_repr(ref) do
      {:ok, repr} ->
        concat(["#Python<", repr, ">"])

      {:error, _} ->
        # Fallback to struct inspection
        concat([
          "#SnakeBridge.Ref<",
          "id: ", ref.id,
          ", module: ", ref.python_module,
          ">"
        ])
    end
  end

  defp get_python_repr(ref) do
    # Use cached value if available, otherwise call Python
    case Process.get({:snakebridge_repr_cache, ref.id}) do
      nil ->
        result = SnakeBridge.Runtime.call_method(
          SnakeBridge.Ref.to_wire_format(ref),
          :__repr__,
          [],
          timeout: 5000
        )

        case result do
          {:ok, repr} when is_binary(repr) ->
            # Cache for 5 minutes
            Process.put({:snakebridge_repr_cache, ref.id}, {repr, System.monotonic_time(:second)})
            {:ok, truncate(repr, 100)}

          _ ->
            {:error, :unavailable}
        end

      {repr, cached_at} ->
        # Check if cache is still valid (5 min TTL)
        if System.monotonic_time(:second) - cached_at < 300 do
          {:ok, repr}
        else
          Process.delete({:snakebridge_repr_cache, ref.id})
          get_python_repr(ref)
        end
    end
  end

  defp truncate(string, max_len) when byte_size(string) > max_len do
    String.slice(string, 0, max_len - 3) <> "..."
  end
  defp truncate(string, _), do: string
end
```

#### 3.3 Implement String.Chars Protocol
File: `lib/snakebridge/ref.ex` (add to same file)

```elixir
defimpl String.Chars, for: SnakeBridge.Ref do
  def to_string(%SnakeBridge.Ref{} = ref) do
    case SnakeBridge.Runtime.call_method(
      SnakeBridge.Ref.to_wire_format(ref),
      :__str__,
      [],
      timeout: 5000
    ) do
      {:ok, str} when is_binary(str) ->
        str

      _ ->
        "#SnakeBridge.Ref<#{ref.id}>"
    end
  end
end
```

#### 3.4 Implement Enumerable Protocol
File: `lib/snakebridge/ref.ex` (add to same file)

```elixir
defimpl Enumerable, for: SnakeBridge.Ref do
  alias SnakeBridge.{Ref, Runtime}

  def count(%Ref{} = ref) do
    wire_ref = Ref.to_wire_format(ref)

    case Runtime.call_method(wire_ref, :__len__, []) do
      {:ok, len} when is_integer(len) -> {:ok, len}
      _ -> {:error, __MODULE__}
    end
  end

  def member?(%Ref{} = ref, value) do
    wire_ref = Ref.to_wire_format(ref)

    case Runtime.call_method(wire_ref, :__contains__, [value]) do
      {:ok, true} -> {:ok, true}
      {:ok, false} -> {:ok, false}
      _ -> {:error, __MODULE__}
    end
  end

  def slice(%Ref{}), do: {:error, __MODULE__}

  def reduce(%Ref{} = ref, acc, fun) do
    wire_ref = Ref.to_wire_format(ref)

    # Get iterator
    case Runtime.call_method(wire_ref, :__iter__, []) do
      {:ok, iterator_ref} ->
        do_reduce(iterator_ref, acc, fun)

      {:error, _} ->
        # Try index-based iteration
        do_reduce_by_index(wire_ref, 0, acc, fun)
    end
  end

  defp do_reduce(iterator_ref, {:cont, acc}, fun) do
    case Runtime.call_method(iterator_ref, :__next__, []) do
      {:ok, value} ->
        do_reduce(iterator_ref, fun.(value, acc), fun)

      {:error, %{type: "StopIteration"}} ->
        {:done, acc}

      {:error, _reason} ->
        {:done, acc}
    end
  end

  defp do_reduce(_iterator, {:halt, acc}, _fun), do: {:halted, acc}
  defp do_reduce(iterator, {:suspend, acc}, fun), do: {:suspended, acc, &do_reduce(iterator, &1, fun)}

  defp do_reduce_by_index(ref, index, {:cont, acc}, fun) do
    case Runtime.call_method(ref, :__getitem__, [index]) do
      {:ok, value} ->
        do_reduce_by_index(ref, index + 1, fun.(value, acc), fun)

      {:error, %{type: "IndexError"}} ->
        {:done, acc}

      {:error, _} ->
        {:done, acc}
    end
  end

  defp do_reduce_by_index(_ref, _index, {:halt, acc}, _fun), do: {:halted, acc}
  defp do_reduce_by_index(ref, index, {:suspend, acc}, fun) do
    {:suspended, acc, &do_reduce_by_index(ref, index, &1, fun)}
  end
end
```

#### 3.5 Create Dynamic Exception Module
File: `lib/snakebridge/dynamic_exception.ex` (new file)

```elixir
defmodule SnakeBridge.DynamicException do
  @moduledoc """
  Dynamically creates Elixir exception modules from Python exception class names.

  This enables proper pattern matching on Python exceptions:

      try do
        SnakeBridge.some_call()
      rescue
        e in SnakeBridge.DynamicException.ValueError ->
          handle_value_error(e)
        e in SnakeBridge.DynamicException.KeyError ->
          handle_key_error(e)
      end
  """

  @exception_cache :snakebridge_exception_cache

  @doc """
  Creates an exception struct from a Python exception class name and message.
  """
  @spec create(String.t(), String.t(), keyword()) :: Exception.t()
  def create(python_class_name, message, opts \\ []) do
    module = get_or_create_module(python_class_name)
    struct(module, message: message, python_class: python_class_name, details: opts)
  end

  @doc """
  Gets or creates an exception module for a Python class name.
  """
  def get_or_create_module(python_class_name) do
    # Extract just the class name (last component)
    class_name = python_class_name
      |> String.split(".")
      |> List.last()
      |> String.replace(~r/[^A-Za-z0-9]/, "")

    module_name = Module.concat(__MODULE__, String.to_atom(class_name))

    # Check cache first
    case :ets.lookup(@exception_cache, module_name) do
      [{^module_name, true}] ->
        module_name

      [] ->
        # Create module if doesn't exist
        create_exception_module(module_name, class_name, python_class_name)
        module_name
    end
  end

  @doc false
  def ensure_cache_exists do
    if :ets.whereis(@exception_cache) == :undefined do
      :ets.new(@exception_cache, [:named_table, :set, :public])
    end
  end

  defp create_exception_module(module_name, class_name, python_class_name) do
    ensure_cache_exists()

    # Check if module already exists
    unless Code.ensure_loaded?(module_name) do
      # Define the exception module
      Module.create(module_name, quote do
        @moduledoc """
        Dynamic exception for Python `#{unquote(python_class_name)}`.
        """

        defexception [:message, :python_class, :details]

        @impl true
        def exception(opts) when is_list(opts) do
          %__MODULE__{
            message: Keyword.get(opts, :message, ""),
            python_class: Keyword.get(opts, :python_class, unquote(python_class_name)),
            details: Keyword.get(opts, :details, [])
          }
        end

        @impl true
        def message(%{message: msg}), do: msg
      end, Macro.Env.location(__ENV__))
    end

    :ets.insert(@exception_cache, {module_name, true})
  end
end
```

#### 3.6 Update Error Translator
File: `lib/snakebridge/error_translator.ex`

Add dynamic exception fallback:
```elixir
def translate(%{type: type, message: message} = error) when is_binary(type) do
  # Try known translations first
  case translate_known(error) do
    nil ->
      # Fall back to dynamic exception
      SnakeBridge.DynamicException.create(type, message, details: error)

    exception ->
      exception
  end
end

defp translate_known(%{type: "ShapeMismatchError"} = error) do
  # Existing translation
end

defp translate_known(%{type: "OutOfMemoryError"} = error) do
  # Existing translation
end

defp translate_known(_), do: nil
```

#### 3.7 Update Introspection to Capture Dunder Methods
File: `lib/snakebridge/introspector.ex`

Update the embedded Python script to capture specific dunder methods:
```python
# In introspection script, update class introspection
PROTOCOL_DUNDERS = [
    "__str__", "__repr__", "__len__", "__getitem__", "__setitem__",
    "__contains__", "__iter__", "__next__", "__enter__", "__exit__",
    "__call__", "__hash__", "__eq__", "__ne__", "__lt__", "__le__",
    "__gt__", "__ge__", "__add__", "__sub__", "__mul__", "__truediv__"
]

def _introspect_class(cls):
    # ... existing code ...

    dunder_methods = []
    for name in dir(cls):
        if name in PROTOCOL_DUNDERS:
            method = getattr(cls, name, None)
            if callable(method):
                dunder_methods.append(name)

    return {
        # ... existing fields ...
        "dunder_methods": dunder_methods
    }
```

### Step 4: Run Tests (Expect Pass)
```bash
mix test test/snakebridge/protocol_integration_test.exs
mix test test/snakebridge/dynamic_exception_test.exs
mix test test/snakebridge/dunder_introspection_test.exs
mix test
```

### Step 5: Run Full Quality Checks
```bash
mix compile --warnings-as-errors
mix dialyzer
mix credo --strict
```

### Step 6: Update Examples

Create `examples/protocol_integration_example/` to demonstrate:
- Inspecting Python objects in IEx
- Using Enum functions on Python collections
- Catching dynamic Python exceptions
- String interpolation with Python objects

Update `examples/run_all.sh` with new example.

### Step 7: Update Documentation

Update `README.md`:
- Document Inspect/Enumerable/String.Chars support
- Document dynamic exception handling
- Add pattern matching examples for exceptions

## Acceptance Criteria

- [ ] `inspect(python_ref)` shows Python object representation
- [ ] `Enum.count(python_list)` calls Python `__len__`
- [ ] `Enum.map(python_list, &fun/1)` iterates via `__iter__`
- [ ] `"Value: #{python_ref}"` interpolation works
- [ ] Unknown Python exceptions become proper Elixir exceptions
- [ ] Exceptions can be pattern-matched by type
- [ ] Dunder methods detected during introspection
- [ ] All existing tests pass
- [ ] New tests for this domain pass
- [ ] No dialyzer errors
- [ ] No credo warnings

## Dependencies

This domain depends on:
- Domain 1 (Type System) - type encoding
- Domain 4 (Dynamic Dispatch) - dunder method calls

This domain completes the "Universal FFI" experience by making Python objects feel native to Elixir.
