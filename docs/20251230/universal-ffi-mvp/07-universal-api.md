# Fix #7: Universal FFI API Surface

**Status**: Specification
**Priority**: High
**Complexity**: Low
**Estimated Changes**: ~100 lines Elixir (mostly docs)

## Problem Statement

SnakeBridge has all the primitives for universal FFI, but they're scattered:
- `SnakeBridge.Runtime.call_dynamic/4` - dynamic calls
- `SnakeBridge.Runtime.call_method/4` - method calls (internal)
- `SnakeBridge.Dynamic.call/4` - method calls (public)
- `SnakeBridge.Runtime.get_attr/3` - attribute access
- `SnakeBridge.Runtime.get_module_attr/3` - module attribute access

The universal FFI surface should be a **tight set of runtime calls** that:
1. Never require codegen
2. Work with string module paths
3. Always have session IDs
4. Have correct bytes/dict support
5. Are well-documented with examples

## Solution

Create an explicit public API in `lib/snakebridge.ex` that presents the universal FFI capabilities clearly.

## API Design

### Core Functions

```elixir
# Call any Python function
SnakeBridge.call(module, function, args \\ [], opts \\ [])

# Stream results from generator/iterator
SnakeBridge.stream(module, function, args, opts, callback)

# Get module-level attribute (constant, class, etc.)
SnakeBridge.get(module, attr, opts \\ [])

# Call method on a ref
SnakeBridge.method(ref, method, args \\ [], opts \\ [])

# Get attribute from ref
SnakeBridge.attr(ref, attr, opts \\ [])

# Set attribute on ref
SnakeBridge.set_attr(ref, attr, value, opts \\ [])

# Create explicit bytes
SnakeBridge.bytes(data)

# Get current session ID
SnakeBridge.current_session()

# Release auto-session
SnakeBridge.release_auto_session()
```

### Usage Examples

```elixir
# Basic call with string module path
{:ok, result} = SnakeBridge.call("math", "sqrt", [16])
# => {:ok, 4.0}

# With kwargs
{:ok, result} = SnakeBridge.call("builtins", "round", [3.14159], ndigits: 2)
# => {:ok, 3.14}

# Submodule call
{:ok, norm} = SnakeBridge.call("numpy.linalg", "norm", [[3, 4]])
# => {:ok, 5.0}

# Get module constant
{:ok, pi} = SnakeBridge.get("math", "pi")
# => {:ok, 3.141592653589793}

# Object creation and method calls
{:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp/test"])
{:ok, exists?} = SnakeBridge.method(path, "exists", [])
{:ok, name} = SnakeBridge.attr(path, "name")

# Streaming
SnakeBridge.stream("pandas", "read_csv", ["large.csv"], [chunksize: 1000], fn chunk ->
  process_chunk(chunk)
end)

# Binary data
{:ok, hash_ref} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])
{:ok, hex} = SnakeBridge.method(hash_ref, "hexdigest", [])
```

## Implementation Details

### File: `lib/snakebridge.ex`

```elixir
defmodule SnakeBridge do
  @moduledoc """
  Universal FFI bridge to Python.

  SnakeBridge provides two ways to call Python:

  1. **Generated wrappers** (compile-time): Type-safe, documented Elixir modules
     generated from Python library introspection.

  2. **Dynamic calls** (runtime): Direct calls to any Python module without
     code generation, using string module paths.

  ## Universal FFI API

  The universal FFI requires no code generation:

      # Call any Python function
      {:ok, result} = SnakeBridge.call("math", "sqrt", [16])

      # Get module attributes
      {:ok, pi} = SnakeBridge.get("math", "pi")

      # Work with Python objects
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp"])
      {:ok, exists?} = SnakeBridge.method(path, "exists", [])

  ## Sessions

  SnakeBridge automatically manages Python object sessions. Each Elixir process
  gets an isolated session, and refs are automatically cleaned up when the
  process terminates.

  For explicit session control, use `SnakeBridge.SessionContext.with_session/1`.

  ## Type Mapping

  | Elixir | Python |
  |--------|--------|
  | `nil` | `None` |
  | `true`/`false` | `True`/`False` |
  | integers | `int` |
  | floats | `float` |
  | strings | `str` |
  | `SnakeBridge.bytes(data)` | `bytes` |
  | lists | `list` |
  | maps | `dict` |
  | tuples | `tuple` |
  | `MapSet` | `set` |
  | atoms | tagged atom (decoded to string by default) |
  | `DateTime` | `datetime` |
  | `SnakeBridge.Ref` | Python object reference |
  """

  alias SnakeBridge.{Runtime, Dynamic, Bytes, Ref}

  # ============================================================================
  # Universal FFI API
  # ============================================================================

  @doc """
  Call a Python function.

  Accepts either a generated SnakeBridge module or a Python module path string.

  ## Parameters

  - `module` - A generated module atom (e.g., `Numpy`) or a module path string (e.g., `"numpy"`)
  - `function` - Function name as atom or string
  - `args` - List of positional arguments (default: `[]`)
  - `opts` - Keyword arguments passed to Python, plus:
    - `:idempotent` - Mark call as cacheable (default: `false`)
    - `:__runtime__` - Pass-through options to Snakepit

  ## Examples

      # Call stdlib function
      {:ok, 4.0} = SnakeBridge.call("math", "sqrt", [16])

      # With keyword arguments
      {:ok, 3.14} = SnakeBridge.call("builtins", "round", [3.14159], ndigits: 2)

      # Submodule
      {:ok, path} = SnakeBridge.call("os.path", "join", ["/tmp", "file.txt"])

      # Create objects
      {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])

  ## Return Values

  - `{:ok, value}` - Decoded Elixir value for JSON-serializable results
  - `{:ok, %SnakeBridge.Ref{}}` - Reference for non-serializable Python objects
  - `{:error, reason}` - Error from Python

  ## Notes

  - String module paths trigger dynamic dispatch (no codegen required)
  - Sessions are automatic; refs are isolated per Elixir process
  - Non-JSON-serializable returns are wrapped in refs for safe access
  """
  @spec call(module() | String.t(), atom() | String.t(), list(), keyword()) ::
          {:ok, term()} | {:error, term()}
  defdelegate call(module, function, args \\ [], opts \\ []), to: Runtime

  @doc """
  Call a Python function, raising on error.

  Same as `call/4` but raises on error instead of returning `{:error, reason}`.

  ## Examples

      result = SnakeBridge.call!("math", "sqrt", [16])
      # => 4.0

      # Raises on error
      SnakeBridge.call!("math", "sqrt", [-1])
      # ** (SnakeBridge.Error) ...
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

  Retrieves constants, classes, or any attribute from a Python module.

  ## Parameters

  - `module` - A generated module atom or a module path string
  - `attr` - Attribute name as atom or string
  - `opts` - Runtime options

  ## Examples

      # Module constant
      {:ok, pi} = SnakeBridge.get("math", "pi")
      # => {:ok, 3.141592653589793}

      # Module-level class (returns ref)
      {:ok, path_class} = SnakeBridge.get("pathlib", "Path")

      # Nested attribute
      {:ok, sep} = SnakeBridge.get("os", "sep")
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

  Calls a Python function that returns an iterable and invokes the callback
  for each element.

  ## Parameters

  - `module` - Module atom or path string
  - `function` - Function name
  - `args` - Positional arguments
  - `opts` - Keyword arguments for the Python function
  - `callback` - Function called with each streamed element

  ## Examples

      # Process file in chunks
      SnakeBridge.stream("pandas", "read_csv", ["large.csv"], [chunksize: 1000], fn chunk ->
        IO.puts("Processing chunk with \#{chunk_size(chunk)} rows")
      end)

      # Iterate range
      SnakeBridge.stream("builtins", "range", [10], [], fn i ->
        IO.puts("Got: \#{i}")
      end)

  ## Return Value

  - `{:ok, :done}` - Iteration completed successfully
  - `{:error, reason}` - Error during iteration
  """
  @spec stream(module() | String.t(), atom() | String.t(), list(), keyword(), (term() -> term())) ::
          {:ok, :done} | {:error, term()}
  defdelegate stream(module, function, args, opts, callback), to: Runtime

  @doc """
  Call a method on a Python object reference.

  ## Parameters

  - `ref` - A `SnakeBridge.Ref` from a previous call
  - `method` - Method name as atom or string
  - `args` - Positional arguments (default: `[]`)
  - `opts` - Keyword arguments

  ## Examples

      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["."])
      {:ok, exists?} = SnakeBridge.method(path, "exists", [])
      {:ok, resolved} = SnakeBridge.method(path, "resolve", [])

      # With arguments
      {:ok, child} = SnakeBridge.method(path, "joinpath", ["subdir", "file.txt"])

  ## Notes

  This is equivalent to `SnakeBridge.Dynamic.call/4` but with a clearer name
  for the universal FFI context.
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

  ## Parameters

  - `ref` - A `SnakeBridge.Ref` from a previous call
  - `attr` - Attribute name as atom or string
  - `opts` - Runtime options

  ## Examples

      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp/file.txt"])
      {:ok, name} = SnakeBridge.attr(path, "name")
      # => {:ok, "file.txt"}

      {:ok, parent} = SnakeBridge.attr(path, "parent")
      # => {:ok, %SnakeBridge.Ref{...}}  # parent is also a Path
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

  ## Parameters

  - `ref` - A `SnakeBridge.Ref` from a previous call
  - `attr` - Attribute name as atom or string
  - `value` - New value for the attribute
  - `opts` - Runtime options

  ## Examples

      {:ok, obj} = SnakeBridge.call("some_module", "SomeClass", [])
      :ok = SnakeBridge.set_attr(obj, "property", "new_value")
  """
  @spec set_attr(Ref.t(), atom() | String.t(), term(), keyword()) ::
          :ok | {:error, term()}
  defdelegate set_attr(ref, attr, value, opts \\ []), to: Dynamic

  # ============================================================================
  # Type Helpers
  # ============================================================================

  @doc """
  Create a Bytes wrapper for explicit binary data.

  By default, SnakeBridge encodes UTF-8 valid strings as Python `str`.
  Use this function to explicitly send data as Python `bytes`.

  ## Examples

      # Crypto
      {:ok, hash_ref} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])
      {:ok, hex} = SnakeBridge.method(hash_ref, "hexdigest", [])

      # Binary protocols
      {:ok, packed} = SnakeBridge.call("struct", "pack", [">I", 12345])

      # Base64
      {:ok, encoded} = SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes("hello")])

  ## When to Use

  Python distinguishes `str` (text) from `bytes` (binary). Use `bytes/1` for:
  - Cryptographic operations (hashlib, hmac, cryptography)
  - Binary packing (struct)
  - Base64 encoding
  - Network protocols
  - File I/O in binary mode
  """
  @spec bytes(binary()) :: Bytes.t()
  def bytes(data) when is_binary(data) do
    Bytes.new(data)
  end

  # ============================================================================
  # Session Management
  # ============================================================================

  @doc """
  Get the current session ID.

  Returns the session ID for the current Elixir process. Sessions are
  automatically created on first Python call.

  ## Examples

      session_id = SnakeBridge.current_session()
      # => "auto_<0.123.0>_1703944800000"

      # With explicit session
      SnakeBridge.SessionContext.with_session(session_id: "my_session", fn ->
        SnakeBridge.current_session()
      end)
      # => "my_session"
  """
  @spec current_session() :: String.t()
  defdelegate current_session(), to: Runtime

  @doc """
  Release and clear the auto-session for the current process.

  Call this to eagerly release Python object refs when you're done with
  Python calls, rather than waiting for process termination.

  ## Examples

      {:ok, ref} = SnakeBridge.call("numpy", "array", [[1,2,3]])
      # ... use ref ...
      SnakeBridge.release_auto_session()  # Clean up now

  ## Notes

  - This releases all refs in the current process's auto-session
  - A new session is created automatically on the next Python call
  - Use `SessionContext.with_session/1` for more fine-grained control
  """
  @spec release_auto_session() :: :ok
  defdelegate release_auto_session(), to: Runtime

  # ============================================================================
  # Ref Utilities
  # ============================================================================

  @doc """
  Check if a value is a Python object reference.

  ## Examples

      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["."])
      SnakeBridge.ref?(path)
      # => true

      SnakeBridge.ref?("string")
      # => false
  """
  @spec ref?(term()) :: boolean()
  defdelegate ref?(value), to: Ref
end
```

## Test Specifications

### File: `test/snakebridge/universal_api_test.exs` (NEW)

```elixir
defmodule SnakeBridge.UniversalApiTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  describe "call/4" do
    test "calls Python function with string module" do
      {:ok, result} = SnakeBridge.call("math", "sqrt", [16])
      assert result == 4.0
    end

    test "accepts atom function names" do
      {:ok, result} = SnakeBridge.call("math", :sqrt, [16])
      assert result == 4.0
    end

    test "passes kwargs" do
      {:ok, result} = SnakeBridge.call("builtins", "round", [3.14159], ndigits: 2)
      assert result == 3.14
    end
  end

  describe "call!/4" do
    test "returns result on success" do
      assert SnakeBridge.call!("math", "sqrt", [16]) == 4.0
    end

    test "raises on error" do
      assert_raise Snakepit.Error, fn ->
        SnakeBridge.call!("nonexistent_module", "fn", [])
      end
    end
  end

  describe "get/3" do
    test "gets module constant" do
      {:ok, pi} = SnakeBridge.get("math", "pi")
      assert_in_delta pi, 3.14159, 0.001
    end

    test "gets module with atom attr" do
      {:ok, e} = SnakeBridge.get("math", :e)
      assert_in_delta e, 2.71828, 0.001
    end
  end

  describe "method/4" do
    test "calls method on ref" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["."])
      {:ok, exists?} = SnakeBridge.method(path, "exists", [])
      assert is_boolean(exists?)
    end

    test "accepts atom method names" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["."])
      {:ok, _} = SnakeBridge.method(path, :exists, [])
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

    test "works with crypto calls" do
      {:ok, ref} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])
      {:ok, hex} = SnakeBridge.method(ref, "hexdigest", [])
      assert hex == "900150983cd24fb0d6963f7d28e17f72"
    end
  end

  describe "session management" do
    test "current_session returns session id" do
      {:ok, _} = SnakeBridge.call("math", "sqrt", [4])
      session = SnakeBridge.current_session()
      assert is_binary(session)
      assert String.starts_with?(session, "auto_")
    end

    test "release_auto_session cleans up" do
      {:ok, _} = SnakeBridge.call("math", "sqrt", [4])
      old_session = SnakeBridge.current_session()

      :ok = SnakeBridge.release_auto_session()

      {:ok, _} = SnakeBridge.call("math", "sqrt", [9])
      new_session = SnakeBridge.current_session()

      assert old_session != new_session
    end
  end

  describe "ref?/1" do
    test "returns true for refs" do
      {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
      assert SnakeBridge.ref?(ref)
    end

    test "returns false for non-refs" do
      refute SnakeBridge.ref?("string")
      refute SnakeBridge.ref?(123)
      refute SnakeBridge.ref?(%{})
    end
  end
end
```

## Documentation Updates

### README.md additions

Add a "Universal FFI" section:

```markdown
## Universal FFI

SnakeBridge provides a universal FFI that works with any Python module
without code generation:

```elixir
# Call any Python function
{:ok, result} = SnakeBridge.call("math", "sqrt", [16])

# Work with Python objects
{:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp"])
{:ok, exists?} = SnakeBridge.method(path, "exists", [])
{:ok, name} = SnakeBridge.attr(path, "name")

# Get module attributes
{:ok, pi} = SnakeBridge.get("math", "pi")

# Binary data for crypto/protocols
{:ok, hash} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])
```

### Key Features

- **No codegen required**: Just pass string module paths
- **Automatic sessions**: Refs are isolated per Elixir process
- **Safe ref handling**: Non-serializable Python objects become refs
- **Type-aware**: Explicit bytes, tagged dicts, proper type mapping

See the [Universal FFI Guide](docs/universal_ffi.md) for details.
```

## Edge Cases

1. **Mixed API usage**: Using both generated modules and string paths in same process
2. **Bang functions with non-Error exceptions**: Ensure proper exception raising
3. **Ref passed to wrong session**: Should fail gracefully

## Backwards Compatibility

- **Fully compatible**: All new functions, no changes to existing behavior
- **Existing API preserved**: `Runtime.call_dynamic/4` etc. still work
- **New convenience layer**: Clean API on top of existing primitives

## Related Changes

- Requires [01-string-module-paths.md](./01-string-module-paths.md) for string path support
- Requires [02-auto-session.md](./02-auto-session.md) for automatic sessions
- Uses [03-explicit-bytes.md](./03-explicit-bytes.md) for `bytes/1`
- Depends on [04-tagged-dict.md](./04-tagged-dict.md) for proper dict handling
- Depends on [05-encoder-fallback.md](./05-encoder-fallback.md) for error handling
- Depends on [06-python-ref-safety.md](./06-python-ref-safety.md) for reliable refs
