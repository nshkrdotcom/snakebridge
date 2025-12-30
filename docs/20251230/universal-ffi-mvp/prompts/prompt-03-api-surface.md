# Prompt 03: String Module Paths and Universal API

**Objective**: Enable string module paths in `call/4` and add the universal FFI public API.

**Dependencies**: Prompts 01 and 02 must be completed first.

## Required Reading

Before starting, read these files completely:

### Documentation
- `docs/20251230/universal-ffi-mvp/00-overview.md` - Full context
- `docs/20251230/universal-ffi-mvp/01-string-module-paths.md` - String paths spec
- `docs/20251230/universal-ffi-mvp/07-universal-api.md` - Universal API spec

### Source Files
- `lib/snakebridge.ex` - Main module
- `lib/snakebridge/runtime.ex` - Runtime implementation
- `lib/snakebridge/dynamic.ex` - Dynamic dispatch
- `lib/snakebridge/ref.ex` - Ref struct

## Implementation Tasks

### Task 1: Update Runtime.call/4 for String Modules

Modify `lib/snakebridge/runtime.ex`:

1. Update typespec:
   ```elixir
   @spec call(module_ref() | String.t(), function_name() | String.t(), args(), opts()) ::
           {:ok, term()} | {:error, Snakepit.Error.t()}
   ```

2. Add string module clause (BEFORE atom clause):
   ```elixir
   def call(module, function, args \\ [], opts \\ [])

   def call(module, function, args, opts) when is_binary(module) do
     function_name = to_string(function)
     call_dynamic(module, function_name, args, opts)
   end

   def call(module, function, args, opts) when is_atom(module) do
     # ... existing implementation ...
   end
   ```

### Task 2: Update Runtime.stream/5 for String Modules

1. Update typespec:
   ```elixir
   @spec stream(module_ref() | String.t(), function_name() | String.t(), args(), opts(), callback()) ::
           {:ok, term()} | {:error, Snakepit.Error.t()}
   ```

2. Add string module clause:
   ```elixir
   def stream(module, function, args, opts, callback)

   def stream(module, function, args, opts, callback) when is_binary(module) do
     function_name = to_string(function)
     stream_dynamic(module, function_name, args, opts, callback)
   end

   def stream(module, function, args, opts, callback) when is_atom(module) do
     # ... existing implementation ...
   end
   ```

3. Add `stream_dynamic/5` if not exists:
   ```elixir
   @spec stream_dynamic(String.t(), String.t(), args(), opts(), callback()) ::
           {:ok, term()} | {:error, term()}
   def stream_dynamic(module_path, function, args, opts, callback) when is_binary(module_path) do
     case call_dynamic(module_path, function, args, opts) do
       {:ok, %SnakeBridge.StreamRef{} = stream_ref} ->
         stream_iterate(stream_ref, callback, [])
       {:ok, %SnakeBridge.Ref{} = ref} ->
         stream_iterate_ref(ref, callback, [])
       {:ok, other} ->
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
       error ->
         error
     end
   end
   ```

### Task 3: Update Runtime.get_module_attr/3 for String Modules

1. Update typespec:
   ```elixir
   @spec get_module_attr(module_ref() | String.t(), atom() | String.t(), opts()) ::
           {:ok, term()} | {:error, term()}
   ```

2. Add string module clause:
   ```elixir
   def get_module_attr(module, attr, opts \\ [])

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

   def get_module_attr(module, attr, opts) when is_atom(module) do
     # ... existing implementation ...
   end

   defp library_from_module_path(module_path) when is_binary(module_path) do
     module_path |> String.split(".") |> List.first()
   end
   ```

### Task 4: Add Universal API to SnakeBridge Module

Update `lib/snakebridge.ex` with the full universal API:

```elixir
defmodule SnakeBridge do
  @moduledoc """
  Universal FFI bridge to Python.
  [Full moduledoc from 07-universal-api.md]
  """

  alias SnakeBridge.{Runtime, Dynamic, Bytes, Ref}

  # ============================================================================
  # Universal FFI API
  # ============================================================================

  @doc """
  Call a Python function.
  [Full doc from 07-universal-api.md]
  """
  @spec call(module() | String.t(), atom() | String.t(), list(), keyword()) ::
          {:ok, term()} | {:error, term()}
  defdelegate call(module, function, args \\ [], opts \\ []), to: Runtime

  @doc """
  Call a Python function, raising on error.
  """
  @spec call!(module() | String.t(), atom() | String.t(), list(), keyword()) :: term()
  def call!(module, function, args \\ [], opts \\ []) do
    case call(module, function, args, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Get a module-level attribute from Python.
  """
  @spec get(module() | String.t(), atom() | String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  defdelegate get(module, attr, opts \\ []), to: Runtime, as: :get_module_attr

  @doc """
  Get a module-level attribute, raising on error.
  """
  @spec get!(module() | String.t(), atom() | String.t(), keyword()) :: term()
  def get!(module, attr, opts \\ []) do
    case get(module, attr, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Stream results from a Python generator or iterator.
  """
  @spec stream(module() | String.t(), atom() | String.t(), list(), keyword(), (term() -> term())) ::
          {:ok, :done} | {:error, term()}
  defdelegate stream(module, function, args, opts, callback), to: Runtime

  @doc """
  Call a method on a Python object reference.
  """
  @spec method(Ref.t(), atom() | String.t(), list(), keyword()) ::
          {:ok, term()} | {:error, term()}
  defdelegate method(ref, method, args \\ [], opts \\ []), to: Dynamic, as: :call

  @doc """
  Call a method on a ref, raising on error.
  """
  @spec method!(Ref.t(), atom() | String.t(), list(), keyword()) :: term()
  def method!(ref, method, args \\ [], opts \\ []) do
    case method(ref, method, args, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Get an attribute from a Python object reference.
  """
  @spec attr(Ref.t(), atom() | String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  defdelegate attr(ref, attr, opts \\ []), to: Dynamic, as: :get_attr

  @doc """
  Get an attribute from a ref, raising on error.
  """
  @spec attr!(Ref.t(), atom() | String.t(), keyword()) :: term()
  def attr!(ref, attr, opts \\ []) do
    case attr(ref, attr, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Set an attribute on a Python object reference.
  """
  @spec set_attr(Ref.t(), atom() | String.t(), term(), keyword()) ::
          :ok | {:error, term()}
  defdelegate set_attr(ref, attr, value, opts \\ []), to: Dynamic

  # ============================================================================
  # Type Helpers
  # ============================================================================

  @doc """
  Create a Bytes wrapper for explicit binary data.
  [Full doc from 07-universal-api.md]
  """
  @spec bytes(binary()) :: Bytes.t()
  def bytes(data) when is_binary(data), do: Bytes.new(data)

  # ============================================================================
  # Session Management
  # ============================================================================

  @doc """
  Get the current session ID.
  """
  @spec current_session() :: String.t()
  defdelegate current_session(), to: Runtime

  @doc """
  Release and clear the auto-session for the current process.
  """
  @spec release_auto_session() :: :ok
  defdelegate release_auto_session(), to: Runtime

  # ============================================================================
  # Ref Utilities
  # ============================================================================

  @doc """
  Check if a value is a Python object reference.
  """
  @spec ref?(term()) :: boolean()
  defdelegate ref?(value), to: Ref
end
```

### Task 5: Write Tests (TDD)

Create `test/snakebridge/runtime_string_module_test.exs`:

```elixir
defmodule SnakeBridge.RuntimeStringModuleTest do
  use ExUnit.Case, async: true

  describe "call/4 with string module" do
    test "calls Python stdlib" do
      {:ok, result} = SnakeBridge.Runtime.call("math", "sqrt", [16])
      assert result == 4.0
    end

    test "accepts atom function name" do
      {:ok, result} = SnakeBridge.Runtime.call("math", :sqrt, [16])
      assert result == 4.0
    end

    test "calls submodule" do
      {:ok, result} = SnakeBridge.Runtime.call("os.path", "join", ["/tmp", "file"])
      assert result == "/tmp/file"
    end

    test "passes kwargs" do
      {:ok, result} = SnakeBridge.Runtime.call("builtins", "round", [3.14159], ndigits: 2)
      assert result == 3.14
    end

    test "returns ref for non-JSON objects" do
      {:ok, ref} = SnakeBridge.Runtime.call("pathlib", "Path", ["."])
      assert %SnakeBridge.Ref{} = ref
    end

    test "returns error for non-existent module" do
      {:error, _} = SnakeBridge.Runtime.call("nonexistent_xyz", "fn", [])
    end
  end

  describe "get_module_attr/3 with string module" do
    test "gets constant" do
      {:ok, pi} = SnakeBridge.Runtime.get_module_attr("math", "pi")
      assert_in_delta pi, 3.14159, 0.001
    end

    test "accepts atom attr" do
      {:ok, e} = SnakeBridge.Runtime.get_module_attr("math", :e)
      assert_in_delta e, 2.71828, 0.001
    end
  end
end
```

Create `test/snakebridge/universal_api_test.exs`:

```elixir
defmodule SnakeBridge.UniversalApiTest do
  use ExUnit.Case, async: true

  describe "call/4" do
    test "calls Python function" do
      {:ok, result} = SnakeBridge.call("math", "sqrt", [16])
      assert result == 4.0
    end
  end

  describe "call!/4" do
    test "returns result on success" do
      assert SnakeBridge.call!("math", "sqrt", [16]) == 4.0
    end

    test "raises on error" do
      assert_raise RuntimeError, fn ->
        SnakeBridge.call!("nonexistent", "fn", [])
      end
    end
  end

  describe "get/3" do
    test "gets module constant" do
      {:ok, pi} = SnakeBridge.get("math", "pi")
      assert_in_delta pi, 3.14159, 0.001
    end
  end

  describe "method/4" do
    test "calls method on ref" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["."])
      {:ok, exists?} = SnakeBridge.method(path, "exists", [])
      assert is_boolean(exists?)
    end
  end

  describe "attr/3" do
    test "gets attribute from ref" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp/test.txt"])
      {:ok, name} = SnakeBridge.attr(path, "name")
      assert name == "test.txt"
    end
  end

  describe "bytes/1" do
    test "creates Bytes struct" do
      bytes = SnakeBridge.bytes("hello")
      assert %SnakeBridge.Bytes{data: "hello"} = bytes
    end
  end

  describe "ref?/1" do
    test "returns true for refs" do
      {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
      assert SnakeBridge.ref?(ref)
    end

    test "returns false for non-refs" do
      refute SnakeBridge.ref?("string")
    end
  end
end
```

## Verification Checklist

Run after implementation:

```bash
# Run new tests
mix test test/snakebridge/runtime_string_module_test.exs
mix test test/snakebridge/universal_api_test.exs

# Run all tests
mix test

# Check types
mix dialyzer

# Check code quality
mix credo --strict

# Verify no warnings
mix compile --warnings-as-errors
```

All must pass with:
- ✅ All tests passing
- ✅ No dialyzer errors
- ✅ No credo issues
- ✅ No compilation warnings

## CHANGELOG Entry

Update `CHANGELOG.md` 0.8.4 entry:

```markdown
### Added
- Universal FFI: `SnakeBridge.call/4` now accepts string module paths for dynamic Python calls
- Universal FFI: `SnakeBridge.stream/5` accepts string module paths
- Universal FFI: `SnakeBridge.get/3` for module attributes with string paths
- `SnakeBridge.call!/4`, `SnakeBridge.get!/3`, `SnakeBridge.method!/4`, `SnakeBridge.attr!/3` bang variants
- `SnakeBridge.method/4` as alias for `Dynamic.call/4`
- `SnakeBridge.attr/3` as alias for `Dynamic.get_attr/3`
- `SnakeBridge.ref?/1` to check if a value is a Python ref

### Changed
- `SnakeBridge.call/4` dispatches to `call_dynamic/4` when given string module path
```

## Notes

- String module path clauses must come BEFORE atom module clauses (guard specificity)
- `to_string(function)` handles both atom and string function names
- The universal API is a thin layer over existing Runtime/Dynamic functions
- Bang variants raise the error directly (not wrapped in a custom exception)
- Ensure delegated functions in SnakeBridge have proper `@spec` annotations
