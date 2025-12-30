# Fix #1: String Module Paths

**Status**: Specification
**Priority**: Critical
**Complexity**: Medium
**Estimated Changes**: ~100 lines Elixir

## Problem Statement

The README implies this works:

```elixir
SnakeBridge.call("math", "sqrt", [16])
```

But `SnakeBridge.Runtime.call/4` delegates to `python_module_name/1`, which only works for Elixir modules with `@snakebridge_*` attributes. Binary strings fall through to `"unknown"`:

```elixir
# Current implementation in runtime.ex
defp python_module_name(module) when is_atom(module) do
  case module.__info__(:attributes)[:snakebridge_python_module] do
    [python_module] -> python_module
    _ -> "unknown"
  end
end

# No clause for is_binary(module) - falls through to unknown
```

This makes `SnakeBridge.call/3,4` unusable as a universal FFI entry point.

## Solution

Make `SnakeBridge.Runtime.call/4` and related functions accept **either**:
- A generated Elixir module (current behavior), **or**
- A Python module path string (delegate to `call_dynamic`)

### API Design

```elixir
# Existing - generated module
{:ok, result} = SnakeBridge.call(Numpy, :mean, [[1,2,3]], axis: 0)

# New - string module path (dynamic)
{:ok, result} = SnakeBridge.call("numpy", "mean", [[1,2,3]], axis: 0)
{:ok, result} = SnakeBridge.call("numpy", :mean, [[1,2,3]], axis: 0)  # atom fn name OK too

# Works with submodules
{:ok, result} = SnakeBridge.call("numpy.linalg", "norm", [[1,2,3]])

# Works with streaming
SnakeBridge.stream("pandas", "read_csv", ["large.csv"], [chunksize: 1000], fn chunk ->
  process(chunk)
end)
```

## Implementation Details

### File: `lib/snakebridge/runtime.ex`

#### Change 1: Add string module clause to `call/4`

```elixir
@doc """
Call a Python function.

## Parameters
- `module` - Either a generated SnakeBridge module atom OR a Python module path string
- `function` - Function name (atom or string)
- `args` - Positional arguments (list)
- `opts` - Options including kwargs, :idempotent, :__runtime__

## Examples

    # With generated module
    {:ok, result} = SnakeBridge.Runtime.call(Numpy, :mean, [[1,2,3]])

    # With string module path (dynamic)
    {:ok, result} = SnakeBridge.Runtime.call("numpy", "mean", [[1,2,3]])
"""
@spec call(module_ref() | String.t(), function_name() | String.t(), args(), opts()) ::
        {:ok, term()} | {:error, Snakepit.Error.t()}
def call(module, function, args \\ [], opts \\ [])

# String module path - delegate to dynamic
def call(module, function, args, opts) when is_binary(module) do
  function_name = to_string(function)
  call_dynamic(module, function_name, args, opts)
end

# Atom module - existing behavior
def call(module, function, args, opts) when is_atom(module) do
  # ... existing implementation ...
end
```

#### Change 2: Add string module clause to `stream/5`

```elixir
@doc """
Stream results from a Python generator/iterator.

## Parameters
- `module` - Either a generated SnakeBridge module atom OR a Python module path string
- `function` - Function name (atom or string)
- `args` - Positional arguments (list)
- `opts` - Options including kwargs
- `callback` - Function called for each streamed item

## Examples

    # With string module path
    SnakeBridge.Runtime.stream("pandas", "read_csv", ["file.csv"], [chunksize: 100], fn chunk ->
      process(chunk)
    end)
"""
@spec stream(module_ref() | String.t(), function_name() | String.t(), args(), opts(), callback()) ::
        {:ok, term()} | {:error, Snakepit.Error.t()}
def stream(module, function, args, opts, callback)

# String module path - use stream_dynamic
def stream(module, function, args, opts, callback) when is_binary(module) do
  function_name = to_string(function)
  stream_dynamic(module, function_name, args, opts, callback)
end

# Atom module - existing behavior
def stream(module, function, args, opts, callback) when is_atom(module) do
  # ... existing implementation ...
end
```

#### Change 3: Add `stream_dynamic/5` if not exists

If `stream_dynamic/5` doesn't exist, add it:

```elixir
@doc """
Stream results from a Python generator using dynamic dispatch.

Creates a stream reference and iterates via stream_next until exhausted.
"""
@spec stream_dynamic(String.t(), String.t(), args(), opts(), callback()) ::
        {:ok, term()} | {:error, term()}
def stream_dynamic(module_path, function, args, opts, callback) when is_binary(module_path) do
  {kwargs, _idempotent, extra_args, runtime_opts} = split_opts(opts)

  # First call to get the stream/iterator
  case call_dynamic(module_path, function, args ++ extra_args, opts) do
    {:ok, %SnakeBridge.StreamRef{} = stream_ref} ->
      stream_iterate(stream_ref, callback, runtime_opts)

    {:ok, %SnakeBridge.Ref{} = ref} ->
      # Try to iterate if it's an iterator
      stream_iterate_ref(ref, callback, runtime_opts)

    {:ok, other} ->
      # Not a stream/iterator - return as single value
      {:ok, callback.(other)}

    error ->
      error
  end
end

defp stream_iterate(stream_ref, callback, opts) do
  case stream_next(stream_ref, opts) do
    {:ok, item} ->
      callback.(item)
      stream_iterate(stream_ref, callback, opts)

    {:error, :stop_iteration} ->
      {:ok, :done}

    {:error, _} = error ->
      error
  end
end
```

#### Change 4: Add string module clause to `get_module_attr/3`

```elixir
@doc """
Get a module-level attribute from Python.

## Parameters
- `module` - Either a generated SnakeBridge module atom OR a Python module path string
- `attr` - Attribute name (atom or string)
- `opts` - Runtime options

## Examples

    # Get numpy.pi
    {:ok, pi} = SnakeBridge.Runtime.get_module_attr("numpy", "pi")
    {:ok, pi} = SnakeBridge.Runtime.get_module_attr("numpy", :pi)
"""
@spec get_module_attr(module_ref() | String.t(), atom() | String.t(), opts()) ::
        {:ok, term()} | {:error, term()}
def get_module_attr(module, attr, opts \\ [])

# String module path
def get_module_attr(module, attr, opts) when is_binary(module) do
  {_kwargs, _idempotent, _extra_args, runtime_opts} = split_opts(opts)
  attr_name = to_string(attr)
  session_id = current_session_id()

  payload = %{
    "protocol_version" => @protocol_version,
    "min_supported_version" => @min_supported_version,
    "call_type" => "module_attr",
    "python_module" => module,
    "library" => library_from_module_path(module),
    "attr" => attr_name,
    "session_id" => session_id
  }

  case runtime_client().execute("snakebridge.call", payload, runtime_opts) do
    {:ok, result} -> {:ok, Types.decode(result)}
    error -> error
  end
end

# Atom module - existing behavior
def get_module_attr(module, attr, opts) when is_atom(module) do
  # ... existing implementation ...
end

# Helper to extract library name from module path
defp library_from_module_path(module_path) when is_binary(module_path) do
  module_path
  |> String.split(".")
  |> List.first()
end
```

### File: `lib/snakebridge.ex`

Add delegating functions at the top-level module:

```elixir
@doc """
Call a Python function.

Accepts either a generated SnakeBridge module or a Python module path string.

## Examples

    # Generated module
    {:ok, result} = SnakeBridge.call(Numpy, :mean, [[1,2,3]])

    # String module path (dynamic, no codegen required)
    {:ok, result} = SnakeBridge.call("numpy", "mean", [[1,2,3]])
    {:ok, result} = SnakeBridge.call("numpy.linalg", "norm", [[1,2,3]])

## Options

- Keyword arguments are passed as Python kwargs
- `:idempotent` - Mark call as idempotent for caching
- `:__runtime__` - Pass-through options to Snakepit
"""
defdelegate call(module, function, args \\ [], opts \\ []), to: SnakeBridge.Runtime

@doc """
Stream results from a Python generator/iterator.

## Examples

    SnakeBridge.stream("pandas", "read_csv", ["file.csv"], [chunksize: 100], fn chunk ->
      IO.inspect(chunk)
    end)
"""
defdelegate stream(module, function, args, opts, callback), to: SnakeBridge.Runtime
```

## Test Specifications

### File: `test/snakebridge/runtime_string_module_test.exs`

```elixir
defmodule SnakeBridge.RuntimeStringModuleTest do
  use ExUnit.Case, async: true

  describe "call/4 with string module path" do
    test "calls Python stdlib module" do
      {:ok, result} = SnakeBridge.Runtime.call("math", "sqrt", [16])
      assert result == 4.0
    end

    test "calls Python stdlib with atom function name" do
      {:ok, result} = SnakeBridge.Runtime.call("math", :sqrt, [16])
      assert result == 4.0
    end

    test "calls submodule with dot notation" do
      {:ok, result} = SnakeBridge.Runtime.call("os.path", "join", ["/tmp", "file.txt"])
      assert result == "/tmp/file.txt"
    end

    test "passes kwargs correctly" do
      # round(2.567, ndigits=2) == 2.57
      {:ok, result} = SnakeBridge.Runtime.call("builtins", "round", [2.567], ndigits: 2)
      assert result == 2.57
    end

    test "returns refs for non-JSON objects" do
      {:ok, ref} = SnakeBridge.Runtime.call("pathlib", "Path", ["."])
      assert %SnakeBridge.Ref{} = ref
    end

    test "returns error for non-existent module" do
      {:error, error} = SnakeBridge.Runtime.call("nonexistent_module_xyz", "fn", [])
      assert error.type in [:module_not_found, :import_error]
    end

    test "returns error for non-existent function" do
      {:error, error} = SnakeBridge.Runtime.call("math", "nonexistent_fn_xyz", [])
      assert error.type == :attribute_error
    end
  end

  describe "get_module_attr/3 with string module path" do
    test "gets module constant" do
      {:ok, pi} = SnakeBridge.Runtime.get_module_attr("math", "pi")
      assert_in_delta pi, 3.14159, 0.001
    end

    test "gets module constant with atom attr name" do
      {:ok, e} = SnakeBridge.Runtime.get_module_attr("math", :e)
      assert_in_delta e, 2.71828, 0.001
    end

    test "gets submodule attribute" do
      {:ok, sep} = SnakeBridge.Runtime.get_module_attr("os", "sep")
      assert is_binary(sep)
    end
  end

  describe "stream/5 with string module path" do
    test "streams generator results" do
      results = []

      {:ok, :done} = SnakeBridge.Runtime.stream(
        "builtins",
        "range",
        [5],
        [],
        fn item ->
          send(self(), {:item, item})
        end
      )

      # Collect results
      items = collect_messages([])
      assert items == [0, 1, 2, 3, 4]
    end

    defp collect_messages(acc) do
      receive do
        {:item, item} -> collect_messages(acc ++ [item])
      after
        100 -> acc
      end
    end
  end
end
```

## Edge Cases

1. **Empty module path**: Should raise `ArgumentError`
2. **Module path with trailing dot**: Should raise or handle gracefully
3. **Function name as integer**: Should raise `ArgumentError`
4. **Mix of atom module + string function**: Both should work
5. **Unicode module paths**: Should pass through correctly

## Migration Guide

No migration needed - this is purely additive functionality. Existing code using generated modules continues to work unchanged.

## Dialyzer Considerations

The type spec changes from:

```elixir
@spec call(module_ref(), function_name(), args(), opts()) :: ...
```

to:

```elixir
@spec call(module_ref() | String.t(), function_name() | String.t(), args(), opts()) :: ...
```

Ensure `module_ref()` type is defined and the union with `String.t()` is correct.

## Related Changes

- Requires [02-auto-session.md](./02-auto-session.md) to ensure dynamic calls have proper session IDs
- Enables [07-universal-api.md](./07-universal-api.md) to expose clean public API
