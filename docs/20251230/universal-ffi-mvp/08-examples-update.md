# Fix #8: Examples Update for Universal FFI

**Status**: Specification
**Priority**: Medium
**Complexity**: Medium
**Estimated Changes**: ~400 lines across multiple example files + 1 new example

## Problem Statement

The existing 18 examples in `examples/` directory demonstrate various SnakeBridge capabilities, but they don't showcase the new Universal FFI convenience APIs introduced in v0.8.4:

- `SnakeBridge.call/4` with string module paths
- `SnakeBridge.get/3` for module attributes
- `SnakeBridge.stream/5` for dynamic streaming
- `SnakeBridge.method/4`, `attr/3`, `set_attr/4` aliases
- `SnakeBridge.bytes/1` for explicit binary encoding
- `SnakeBridge.current_session/0` and `release_auto_session/0`
- Auto-session per BEAM process

## Analysis of Existing Examples

### Examples Requiring Updates

| Example | Priority | Updates Needed |
|---------|----------|----------------|
| `dynamic_dispatch_example` | HIGH | Add new convenience APIs alongside existing `Runtime.call_dynamic/4` |
| `types_showcase` | MEDIUM | Add `SnakeBridge.Bytes` examples |
| `session_lifecycle_example` | MEDIUM | Add auto-session demonstration |
| `streaming_example` | LOW | Show `SnakeBridge.stream/5` alternative |

### New Example Needed

| Example | Purpose |
|---------|---------|
| `universal_ffi_example` | Dedicated showcase of all Universal FFI APIs in one place |

## Implementation Details

### 1. Update: `dynamic_dispatch_example`

**Path**: `examples/dynamic_dispatch_example/`

**Current State**: Uses `Runtime.call_dynamic/4` and `Dynamic.*` APIs

**Updates Needed**:

#### File: `lib/dynamic_dispatch_example.ex`

Add new section demonstrating Universal FFI convenience APIs:

```elixir
defmodule DynamicDispatchExample do
  @moduledoc """
  Demonstrates dynamic dispatch (Universal FFI) patterns in SnakeBridge.

  Shows BOTH the lower-level APIs AND the new convenience APIs:
  - `Runtime.call_dynamic/4` vs `SnakeBridge.call/4`
  - `Dynamic.call/4` vs `SnakeBridge.method/4`
  - `Dynamic.get_attr/3` vs `SnakeBridge.attr/3`
  """

  # ============================================================================
  # Original API (v0.7.3+) - Still valid and useful for advanced cases
  # ============================================================================

  @doc "Demonstrates Runtime.call_dynamic/4 - the lower-level API"
  def demo_runtime_call_dynamic do
    IO.puts("\n=== Runtime.call_dynamic/4 ===")

    # Direct Python function call
    {:ok, result} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [16])
    IO.puts("math.sqrt(16) = #{result}")

    # Create object
    {:ok, path_ref} = SnakeBridge.Runtime.call_dynamic("pathlib", "Path", ["."])
    IO.puts("Created Path ref: #{inspect(path_ref)}")

    {:ok, result, path_ref}
  end

  @doc "Demonstrates Dynamic.call/4 for method dispatch"
  def demo_dynamic_call do
    IO.puts("\n=== Dynamic.call/4 ===")

    {:ok, path_ref} = SnakeBridge.Runtime.call_dynamic("pathlib", "Path", ["."])
    {:ok, exists?} = SnakeBridge.Dynamic.call(path_ref, :exists, [])
    IO.puts("path.exists() = #{exists?}")

    {:ok, exists?}
  end

  # ============================================================================
  # New Universal FFI Convenience API (v0.8.4+)
  # ============================================================================

  @doc """
  Demonstrates SnakeBridge.call/4 - the new convenience API.

  This is the RECOMMENDED way to call Python functions dynamically.
  """
  def demo_snakebridge_call do
    IO.puts("\n=== SnakeBridge.call/4 (NEW in v0.8.4) ===")

    # Simple function call with string module path
    {:ok, result} = SnakeBridge.call("math", "sqrt", [16])
    IO.puts("SnakeBridge.call(\"math\", \"sqrt\", [16]) = #{result}")

    # With kwargs
    {:ok, rounded} = SnakeBridge.call("builtins", "round", [3.14159], ndigits: 2)
    IO.puts("round(3.14159, ndigits=2) = #{rounded}")

    # Submodule call
    {:ok, path} = SnakeBridge.call("os.path", "join", ["/tmp", "file.txt"])
    IO.puts("os.path.join(\"/tmp\", \"file.txt\") = #{path}")

    # Create objects - returns ref
    {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
    IO.puts("Created Path: #{inspect(ref)}")

    # Bang variant
    result! = SnakeBridge.call!("math", "sqrt", [25])
    IO.puts("call!(\"math\", \"sqrt\", [25]) = #{result!}")

    {:ok, result}
  end

  @doc "Demonstrates SnakeBridge.get/3 for module attributes"
  def demo_snakebridge_get do
    IO.puts("\n=== SnakeBridge.get/3 (NEW in v0.8.4) ===")

    # Get module constant
    {:ok, pi} = SnakeBridge.get("math", "pi")
    IO.puts("SnakeBridge.get(\"math\", \"pi\") = #{pi}")

    {:ok, e} = SnakeBridge.get("math", :e)  # Atom attr name also works
    IO.puts("SnakeBridge.get(\"math\", :e) = #{e}")

    # Bang variant
    sep = SnakeBridge.get!("os", "sep")
    IO.puts("os.sep = #{inspect(sep)}")

    {:ok, pi}
  end

  @doc "Demonstrates SnakeBridge.method/4, attr/3, set_attr/4"
  def demo_snakebridge_method_attr do
    IO.puts("\n=== SnakeBridge.method/4, attr/3 (NEW in v0.8.4) ===")

    # Create object
    {:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp/test.txt"])

    # Call method (alias for Dynamic.call)
    {:ok, exists?} = SnakeBridge.method(path, "exists", [])
    IO.puts("path.exists() = #{exists?}")

    # Get attribute (alias for Dynamic.get_attr)
    {:ok, name} = SnakeBridge.attr(path, "name")
    IO.puts("path.name = #{name}")

    {:ok, suffix} = SnakeBridge.attr(path, :suffix)  # Atom attr name
    IO.puts("path.suffix = #{suffix}")

    # Bang variants
    stem = SnakeBridge.attr!(path, "stem")
    IO.puts("path.stem = #{stem}")

    {:ok, name}
  end

  @doc "Demonstrates SnakeBridge.ref?/1"
  def demo_ref_check do
    IO.puts("\n=== SnakeBridge.ref?/1 (NEW in v0.8.4) ===")

    {:ok, path_ref} = SnakeBridge.call("pathlib", "Path", ["."])
    {:ok, number} = SnakeBridge.call("math", "sqrt", [16])

    IO.puts("ref?(path_ref) = #{SnakeBridge.ref?(path_ref)}")
    IO.puts("ref?(4.0) = #{SnakeBridge.ref?(number)}")
    IO.puts("ref?(\"string\") = #{SnakeBridge.ref?("string")}")

    :ok
  end

  # ============================================================================
  # Comparison: Old API vs New API
  # ============================================================================

  @doc """
  Side-by-side comparison of old vs new API.

  Both are valid - use the one that fits your needs:
  - New API: Cleaner, recommended for most cases
  - Old API: More explicit, useful for advanced patterns
  """
  def demo_api_comparison do
    IO.puts("\n=== API Comparison ===")

    # OLD: Runtime.call_dynamic/4
    {:ok, r1} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [16])

    # NEW: SnakeBridge.call/4
    {:ok, r2} = SnakeBridge.call("math", "sqrt", [16])

    IO.puts("Runtime.call_dynamic result: #{r1}")
    IO.puts("SnakeBridge.call result:     #{r2}")
    IO.puts("Both equal: #{r1 == r2}")

    # OLD: Dynamic.call/4
    {:ok, path} = SnakeBridge.Runtime.call_dynamic("pathlib", "Path", ["."])
    {:ok, e1} = SnakeBridge.Dynamic.call(path, :exists, [])

    # NEW: SnakeBridge.method/4
    {:ok, path2} = SnakeBridge.call("pathlib", "Path", ["."])
    {:ok, e2} = SnakeBridge.method(path2, :exists, [])

    IO.puts("Dynamic.call result:     #{e1}")
    IO.puts("SnakeBridge.method result: #{e2}")

    :ok
  end

  # ============================================================================
  # Run All Demos
  # ============================================================================

  def run_all do
    IO.puts("=" |> String.duplicate(60))
    IO.puts("Dynamic Dispatch Example - Universal FFI Showcase")
    IO.puts("=" |> String.duplicate(60))

    # Original APIs
    demo_runtime_call_dynamic()
    demo_dynamic_call()

    # New convenience APIs
    demo_snakebridge_call()
    demo_snakebridge_get()
    demo_snakebridge_method_attr()
    demo_ref_check()

    # Comparison
    demo_api_comparison()

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("All demos completed successfully!")
  end
end
```

#### File: `test/dynamic_dispatch_example_test.exs`

Add tests for new APIs:

```elixir
defmodule DynamicDispatchExampleTest do
  use ExUnit.Case

  describe "new Universal FFI convenience APIs" do
    test "SnakeBridge.call/4 with string module" do
      {:ok, result} = SnakeBridge.call("math", "sqrt", [16])
      assert result == 4.0
    end

    test "SnakeBridge.call/4 with kwargs" do
      {:ok, result} = SnakeBridge.call("builtins", "round", [3.14159], ndigits: 2)
      assert result == 3.14
    end

    test "SnakeBridge.get/3 for module constant" do
      {:ok, pi} = SnakeBridge.get("math", "pi")
      assert_in_delta pi, 3.14159, 0.001
    end

    test "SnakeBridge.method/4 calls method on ref" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["."])
      {:ok, exists?} = SnakeBridge.method(path, "exists", [])
      assert is_boolean(exists?)
    end

    test "SnakeBridge.attr/3 gets attribute from ref" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp/test.txt"])
      {:ok, name} = SnakeBridge.attr(path, "name")
      assert name == "test.txt"
    end

    test "SnakeBridge.ref?/1 identifies refs" do
      {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
      assert SnakeBridge.ref?(ref)
      refute SnakeBridge.ref?("string")
      refute SnakeBridge.ref?(42)
    end

    test "bang variants work" do
      assert SnakeBridge.call!("math", "sqrt", [16]) == 4.0
      assert_in_delta SnakeBridge.get!("math", "pi"), 3.14159, 0.001
    end
  end
end
```

---

### 2. Update: `types_showcase`

**Path**: `examples/types_showcase/`

**Updates Needed**: Add `SnakeBridge.Bytes` examples

#### File: `lib/types_showcase.ex`

Add bytes section:

```elixir
@doc """
Demonstrates SnakeBridge.Bytes for explicit binary encoding.

NEW in v0.8.4: Use SnakeBridge.bytes/1 when you need Python bytes, not str.
"""
def demo_bytes do
  IO.puts("\n=== SnakeBridge.Bytes (NEW in v0.8.4) ===")

  # Without bytes wrapper - UTF-8 string sent as Python str
  # This would FAIL for hashlib because it requires bytes
  # {:ok, _} = SnakeBridge.call("hashlib", "md5", ["abc"])  # TypeError!

  # With bytes wrapper - explicitly sent as Python bytes
  {:ok, hash_ref} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])
  {:ok, hex} = SnakeBridge.method(hash_ref, "hexdigest", [])
  IO.puts("md5(b\"abc\") = #{hex}")
  # Expected: 900150983cd24fb0d6963f7d28e17f72

  # base64 encoding
  {:ok, encoded} = SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes("hello")])
  IO.puts("base64.b64encode(b\"hello\") = #{inspect(encoded)}")

  # Binary data round-trip
  original = <<0, 1, 2, 128, 255>>
  {:ok, b64} = SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes(original)])
  {:ok, decoded} = SnakeBridge.call("base64", "b64decode", [b64])
  IO.puts("Binary round-trip: #{original == decoded}")

  {:ok, hex}
end

@doc """
Demonstrates maps with non-string keys (tagged dict wire format).

NEW in v0.8.4: Integer and tuple keys now serialize correctly.
"""
def demo_non_string_key_maps do
  IO.puts("\n=== Non-String Key Maps (NEW in v0.8.4) ===")

  # Integer keys
  int_map = %{1 => "one", 2 => "two", 3 => "three"}
  {:ok, result} = SnakeBridge.call("builtins", "dict", [int_map])
  IO.puts("Integer key map round-trip: #{inspect(result)}")

  # Verify Python sees integer keys (not strings)
  {:ok, dict_ref} = SnakeBridge.call("builtins", "dict", [int_map])
  {:ok, value} = SnakeBridge.method(dict_ref, "get", [1])  # Integer key lookup
  IO.puts("dict.get(1) = #{inspect(value)}")

  # Tuple keys
  tuple_map = %{{0, 0} => "origin", {1, 1} => "diagonal"}
  {:ok, result2} = SnakeBridge.call("builtins", "dict", [tuple_map])
  IO.puts("Tuple key map: #{inspect(result2)}")

  {:ok, result}
end
```

#### File: `test/types_showcase_test.exs`

Add tests:

```elixir
describe "SnakeBridge.Bytes (v0.8.4)" do
  test "bytes wrapper enables hashlib" do
    {:ok, ref} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])
    {:ok, hex} = SnakeBridge.method(ref, "hexdigest", [])
    assert hex == "900150983cd24fb0d6963f7d28e17f72"
  end

  test "binary data round-trips correctly" do
    original = <<0, 1, 2, 128, 255>>
    {:ok, encoded} = SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes(original)])
    {:ok, decoded} = SnakeBridge.call("base64", "b64decode", [encoded])
    assert decoded == original
  end
end

describe "non-string key maps (v0.8.4)" do
  test "integer keys preserved" do
    {:ok, ref} = SnakeBridge.call("builtins", "dict", [%{1 => "one", 2 => "two"}])
    {:ok, value} = SnakeBridge.method(ref, "get", [1])
    assert value == "one"
  end
end
```

---

### 3. Update: `session_lifecycle_example`

**Path**: `examples/session_lifecycle_example/`

**Updates Needed**: Add auto-session demonstration

#### File: `lib/session_lifecycle_example.ex`

Add auto-session section:

```elixir
@doc """
Demonstrates auto-session feature (NEW in v0.8.4).

Sessions are now created automatically per BEAM process.
No need to call with_session/1 for basic usage.
"""
def demo_auto_session do
  IO.puts("\n=== Auto-Session (NEW in v0.8.4) ===")

  # Before any Python call - no session
  IO.puts("Before first call...")

  # First Python call creates auto-session
  {:ok, _} = SnakeBridge.call("math", "sqrt", [16])

  # Check current session
  session_id = SnakeBridge.current_session()
  IO.puts("Auto-session ID: #{session_id}")
  IO.puts("Session starts with 'auto_': #{String.starts_with?(session_id, "auto_")}")

  # Subsequent calls reuse the same session
  {:ok, _} = SnakeBridge.call("math", "sqrt", [25])
  same_session = SnakeBridge.current_session()
  IO.puts("Same session after second call: #{session_id == same_session}")

  # Refs are automatically scoped to this session
  {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
  IO.puts("Ref session_id matches: #{ref.session_id == session_id}")

  {:ok, session_id}
end

@doc """
Demonstrates explicit session release.

Call release_auto_session/0 to eagerly clean up refs.
"""
def demo_session_release do
  IO.puts("\n=== Session Release ===")

  {:ok, _} = SnakeBridge.call("math", "sqrt", [16])
  old_session = SnakeBridge.current_session()
  IO.puts("Current session: #{old_session}")

  # Release the session
  :ok = SnakeBridge.release_auto_session()
  IO.puts("Session released")

  # Next call creates new session
  {:ok, _} = SnakeBridge.call("math", "sqrt", [25])
  new_session = SnakeBridge.current_session()
  IO.puts("New session: #{new_session}")
  IO.puts("Sessions different: #{old_session != new_session}")

  :ok
end

@doc """
Demonstrates process isolation of sessions.

Each BEAM process gets its own session automatically.
"""
def demo_process_isolation do
  IO.puts("\n=== Process Isolation ===")

  # Get session in main process
  {:ok, _} = SnakeBridge.call("math", "sqrt", [16])
  main_session = SnakeBridge.current_session()
  IO.puts("Main process session: #{main_session}")

  # Spawn task - gets different session
  task_session = Task.async(fn ->
    {:ok, _} = SnakeBridge.call("math", "sqrt", [25])
    SnakeBridge.current_session()
  end) |> Task.await()

  IO.puts("Task process session: #{task_session}")
  IO.puts("Sessions isolated: #{main_session != task_session}")

  :ok
end

@doc """
Compares auto-session vs explicit with_session/1.

Both are valid approaches:
- Auto-session: Zero-config, process-scoped
- Explicit session: Fine-grained control, named sessions
"""
def demo_session_comparison do
  IO.puts("\n=== Auto vs Explicit Sessions ===")

  # Auto-session (v0.8.4+ default)
  {:ok, _} = SnakeBridge.call("math", "sqrt", [16])
  auto = SnakeBridge.current_session()
  IO.puts("Auto-session: #{auto}")

  # Explicit session (still works, overrides auto)
  explicit_id = SnakeBridge.SessionContext.with_session(session_id: "my_explicit_session", fn ->
    SnakeBridge.current_session()
  end)
  IO.puts("Explicit session: #{explicit_id}")

  # After with_session block, back to auto
  back_to_auto = SnakeBridge.current_session()
  IO.puts("Back to auto: #{back_to_auto == auto}")

  :ok
end
```

---

### 4. Create: `universal_ffi_example` (NEW)

**Path**: `examples/universal_ffi_example/`

This is a NEW example dedicated to showcasing all Universal FFI features.

#### File: `mix.exs`

```elixir
defmodule UniversalFfiExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :universal_ffi_example,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:snakebridge, path: "../.."}
    ]
  end
end
```

#### File: `lib/universal_ffi_example.ex`

```elixir
defmodule UniversalFfiExample do
  @moduledoc """
  Comprehensive showcase of SnakeBridge Universal FFI (v0.8.4+).

  The Universal FFI enables calling ANY Python module dynamically,
  without compile-time code generation. This is the "escape hatch"
  for libraries not in your generated wrappers, one-off scripts,
  or runtime-determined module paths.

  ## Key APIs Demonstrated

  - `SnakeBridge.call/4` - Call any Python function
  - `SnakeBridge.get/3` - Get module attributes
  - `SnakeBridge.stream/5` - Stream from generators
  - `SnakeBridge.method/4` - Call methods on refs
  - `SnakeBridge.attr/3` - Get attributes from refs
  - `SnakeBridge.set_attr/4` - Set attributes on refs
  - `SnakeBridge.bytes/1` - Explicit binary encoding
  - `SnakeBridge.ref?/1` - Check if value is a ref
  - `SnakeBridge.current_session/0` - Get current session ID
  - `SnakeBridge.release_auto_session/0` - Clean up session
  """

  # ============================================================================
  # Basic Calls
  # ============================================================================

  @doc """
  Basic function calls with string module paths.

  No code generation required - works with any installed Python module.
  """
  def demo_basic_calls do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("1. BASIC CALLS")
    IO.puts(String.duplicate("=", 60))

    # Simple stdlib call
    {:ok, result} = SnakeBridge.call("math", "sqrt", [16])
    IO.puts("math.sqrt(16) = #{result}")

    # With keyword arguments
    {:ok, rounded} = SnakeBridge.call("builtins", "round", [3.14159], ndigits: 2)
    IO.puts("round(3.14159, ndigits=2) = #{rounded}")

    # Submodule paths
    {:ok, path} = SnakeBridge.call("os.path", "join", ["/home", "user", "file.txt"])
    IO.puts("os.path.join(...) = #{path}")

    # Atom function names work too
    {:ok, upper} = SnakeBridge.call("builtins", :str, ["hello"])
    IO.puts("str(\"hello\") = #{upper}")

    :ok
  end

  # ============================================================================
  # Module Attributes
  # ============================================================================

  @doc """
  Getting module-level constants and objects.
  """
  def demo_module_attributes do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("2. MODULE ATTRIBUTES")
    IO.puts(String.duplicate("=", 60))

    # Constants
    {:ok, pi} = SnakeBridge.get("math", "pi")
    IO.puts("math.pi = #{pi}")

    {:ok, e} = SnakeBridge.get("math", "e")
    IO.puts("math.e = #{e}")

    # System info
    {:ok, version} = SnakeBridge.get("sys", "version")
    IO.puts("sys.version = #{String.slice(version, 0..50)}...")

    {:ok, sep} = SnakeBridge.get("os", "sep")
    IO.puts("os.sep = #{inspect(sep)}")

    :ok
  end

  # ============================================================================
  # Object Creation and Methods
  # ============================================================================

  @doc """
  Creating Python objects and calling methods on them.
  """
  def demo_object_methods do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("3. OBJECTS AND METHODS")
    IO.puts(String.duplicate("=", 60))

    # Create a Path object
    {:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp/example.txt"])
    IO.puts("Created: #{inspect(path)}")
    IO.puts("Is ref?: #{SnakeBridge.ref?(path)}")

    # Call methods
    {:ok, exists?} = SnakeBridge.method(path, "exists", [])
    IO.puts("path.exists() = #{exists?}")

    {:ok, is_abs?} = SnakeBridge.method(path, "is_absolute", [])
    IO.puts("path.is_absolute() = #{is_abs?}")

    # Get attributes
    {:ok, name} = SnakeBridge.attr(path, "name")
    IO.puts("path.name = #{name}")

    {:ok, suffix} = SnakeBridge.attr(path, "suffix")
    IO.puts("path.suffix = #{suffix}")

    {:ok, stem} = SnakeBridge.attr(path, "stem")
    IO.puts("path.stem = #{stem}")

    # Method chaining via refs
    {:ok, parent} = SnakeBridge.attr(path, "parent")
    {:ok, parent_name} = SnakeBridge.attr(parent, "name")
    IO.puts("path.parent.name = #{parent_name}")

    :ok
  end

  # ============================================================================
  # Bytes and Binary Data
  # ============================================================================

  @doc """
  Explicit bytes encoding for crypto, protocols, etc.
  """
  def demo_bytes do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("4. BYTES (Binary Data)")
    IO.puts(String.duplicate("=", 60))

    # Hashlib requires bytes, not str
    {:ok, md5_ref} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])
    {:ok, hex} = SnakeBridge.method(md5_ref, "hexdigest", [])
    IO.puts("md5(b\"abc\") = #{hex}")

    # SHA256
    {:ok, sha_ref} = SnakeBridge.call("hashlib", "sha256", [SnakeBridge.bytes("secret")])
    {:ok, sha_hex} = SnakeBridge.method(sha_ref, "hexdigest", [])
    IO.puts("sha256(b\"secret\") = #{String.slice(sha_hex, 0..15)}...")

    # Base64 encoding
    {:ok, encoded} = SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes("hello world")])
    IO.puts("base64.b64encode(b\"hello world\") = #{inspect(encoded)}")

    # Binary data round-trip
    original = <<0, 1, 2, 127, 128, 255>>
    {:ok, b64} = SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes(original)])
    {:ok, decoded} = SnakeBridge.call("base64", "b64decode", [b64])
    IO.puts("Binary round-trip successful: #{original == decoded}")

    :ok
  end

  # ============================================================================
  # Non-String Key Maps
  # ============================================================================

  @doc """
  Maps with integer, tuple, and other non-string keys.
  """
  def demo_non_string_keys do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("5. NON-STRING KEY MAPS")
    IO.puts(String.duplicate("=", 60))

    # Integer keys
    int_map = %{1 => "one", 2 => "two", 3 => "three"}
    {:ok, dict_ref} = SnakeBridge.call("builtins", "dict", [int_map])
    {:ok, value} = SnakeBridge.method(dict_ref, "get", [2])
    IO.puts("dict[2] = #{value}")

    # Verify keys are integers (not strings)
    {:ok, keys} = SnakeBridge.method(dict_ref, "keys", [])
    {:ok, keys_list} = SnakeBridge.call("builtins", "list", [keys])
    IO.puts("Keys: #{inspect(keys_list)}")

    # Tuple keys (coordinate maps, etc.)
    coord_map = %{{0, 0} => "origin", {1, 0} => "x-axis", {0, 1} => "y-axis"}
    {:ok, coord_ref} = SnakeBridge.call("builtins", "dict", [coord_map])
    {:ok, origin} = SnakeBridge.method(coord_ref, "get", [{0, 0}])
    IO.puts("coords[(0,0)] = #{origin}")

    :ok
  end

  # ============================================================================
  # Sessions
  # ============================================================================

  @doc """
  Automatic session management.
  """
  def demo_sessions do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("6. AUTO-SESSIONS")
    IO.puts(String.duplicate("=", 60))

    # Auto-session is created on first call
    {:ok, _} = SnakeBridge.call("math", "sqrt", [16])
    session = SnakeBridge.current_session()
    IO.puts("Auto-session: #{session}")

    # All refs in this process share the session
    {:ok, ref1} = SnakeBridge.call("pathlib", "Path", ["."])
    {:ok, ref2} = SnakeBridge.call("pathlib", "Path", ["/tmp"])
    IO.puts("ref1.session_id: #{ref1.session_id}")
    IO.puts("ref2.session_id: #{ref2.session_id}")
    IO.puts("Same session: #{ref1.session_id == ref2.session_id}")

    # Process isolation
    other_session = Task.async(fn ->
      {:ok, _} = SnakeBridge.call("math", "sqrt", [25])
      SnakeBridge.current_session()
    end) |> Task.await()

    IO.puts("Other process session: #{other_session}")
    IO.puts("Isolated: #{session != other_session}")

    :ok
  end

  # ============================================================================
  # Bang Variants
  # ============================================================================

  @doc """
  Bang (!) variants for raising on error.
  """
  def demo_bang_variants do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("7. BANG VARIANTS")
    IO.puts(String.duplicate("=", 60))

    # call! returns result directly
    result = SnakeBridge.call!("math", "sqrt", [16])
    IO.puts("call!(\"math\", \"sqrt\", [16]) = #{result}")

    # get! for constants
    pi = SnakeBridge.get!("math", "pi")
    IO.puts("get!(\"math\", \"pi\") = #{pi}")

    # method! on refs
    path = SnakeBridge.call!("pathlib", "Path", ["."])
    exists? = SnakeBridge.method!(path, "exists", [])
    IO.puts("method!(path, \"exists\") = #{exists?}")

    # attr! for attributes
    name = SnakeBridge.attr!(path, "name")
    IO.puts("attr!(path, \"name\") = #{name}")

    # Errors raise
    IO.puts("\nAttempting invalid call (will be caught)...")
    try do
      SnakeBridge.call!("nonexistent_module_xyz", "fn", [])
    rescue
      e -> IO.puts("Caught error: #{inspect(e.__struct__)}")
    end

    :ok
  end

  # ============================================================================
  # Streaming
  # ============================================================================

  @doc """
  Streaming from Python generators/iterators.
  """
  def demo_streaming do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("8. STREAMING")
    IO.puts(String.duplicate("=", 60))

    # Stream from range
    IO.puts("Streaming range(5):")
    SnakeBridge.stream("builtins", "range", [5], [], fn item ->
      IO.puts("  Got: #{item}")
    end)

    # Stream with processing
    IO.puts("\nStreaming and summing range(10):")
    sum = Agent.start_link(fn -> 0 end) |> elem(1)
    SnakeBridge.stream("builtins", "range", [10], [], fn item ->
      Agent.update(sum, &(&1 + item))
    end)
    total = Agent.get(sum, & &1)
    Agent.stop(sum)
    IO.puts("Sum: #{total}")

    :ok
  end

  # ============================================================================
  # When to Use Universal FFI vs Generated Wrappers
  # ============================================================================

  @doc """
  Guidance on when to use Universal FFI vs generated wrappers.
  """
  def demo_when_to_use do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("9. WHEN TO USE UNIVERSAL FFI")
    IO.puts(String.duplicate("=", 60))

    IO.puts("""

    USE UNIVERSAL FFI (SnakeBridge.call/4, etc.) when:
    - Calling libraries not in your generated wrappers
    - Module paths are determined at runtime
    - Writing quick scripts or one-off calls
    - Prototyping before adding to libraries config
    - Accessing stdlib modules not worth generating

    USE GENERATED WRAPPERS when:
    - You have a core library you call frequently
    - You want compile-time type hints and docs
    - You want IDE autocomplete
    - You want signature validation at compile time
    - Performance is critical (slightly faster hot path)

    BOTH CAN COEXIST in the same project!

    Example hybrid usage:
    - Generated: NumPy, Pandas (core libraries)
    - Universal: One-off hashlib call, runtime plugins
    """)

    :ok
  end

  # ============================================================================
  # Run All
  # ============================================================================

  def run_all do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("SNAKEBRIDGE UNIVERSAL FFI SHOWCASE")
    IO.puts("Version: 0.8.4+")
    IO.puts(String.duplicate("=", 60))

    demo_basic_calls()
    demo_module_attributes()
    demo_object_methods()
    demo_bytes()
    demo_non_string_keys()
    demo_sessions()
    demo_bang_variants()
    demo_streaming()
    demo_when_to_use()

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("All demos completed!")
    IO.puts(String.duplicate("=", 60))

    :ok
  end
end
```

#### File: `test/universal_ffi_example_test.exs`

```elixir
defmodule UniversalFfiExampleTest do
  use ExUnit.Case

  describe "SnakeBridge.call/4" do
    test "calls function with string module" do
      assert {:ok, 4.0} = SnakeBridge.call("math", "sqrt", [16])
    end

    test "accepts kwargs" do
      assert {:ok, 3.14} = SnakeBridge.call("builtins", "round", [3.14159], ndigits: 2)
    end

    test "works with submodules" do
      assert {:ok, "/tmp/file"} = SnakeBridge.call("os.path", "join", ["/tmp", "file"])
    end
  end

  describe "SnakeBridge.get/3" do
    test "gets module constant" do
      {:ok, pi} = SnakeBridge.get("math", "pi")
      assert_in_delta pi, 3.14159, 0.001
    end
  end

  describe "SnakeBridge.method/4" do
    test "calls method on ref" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["."])
      {:ok, exists?} = SnakeBridge.method(path, "exists", [])
      assert is_boolean(exists?)
    end
  end

  describe "SnakeBridge.attr/3" do
    test "gets attribute from ref" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp/test.txt"])
      assert {:ok, "test.txt"} = SnakeBridge.attr(path, "name")
    end
  end

  describe "SnakeBridge.bytes/1" do
    test "enables hashlib calls" do
      {:ok, ref} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])
      {:ok, hex} = SnakeBridge.method(ref, "hexdigest", [])
      assert hex == "900150983cd24fb0d6963f7d28e17f72"
    end
  end

  describe "non-string key maps" do
    test "integer keys work" do
      {:ok, ref} = SnakeBridge.call("builtins", "dict", [%{1 => "one", 2 => "two"}])
      {:ok, value} = SnakeBridge.method(ref, "get", [1])
      assert value == "one"
    end
  end

  describe "sessions" do
    test "auto-session created on first call" do
      {:ok, _} = SnakeBridge.call("math", "sqrt", [16])
      session = SnakeBridge.current_session()
      assert String.starts_with?(session, "auto_")
    end
  end

  describe "bang variants" do
    test "call! returns result" do
      assert SnakeBridge.call!("math", "sqrt", [16]) == 4.0
    end

    test "call! raises on error" do
      assert_raise RuntimeError, fn ->
        SnakeBridge.call!("nonexistent_xyz", "fn", [])
      end
    end
  end

  describe "ref?/1" do
    test "identifies refs" do
      {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
      assert SnakeBridge.ref?(ref)
      refute SnakeBridge.ref?("string")
    end
  end
end
```

#### File: `README.md`

```markdown
# Universal FFI Example

Comprehensive showcase of SnakeBridge Universal FFI features (v0.8.4+).

## What is Universal FFI?

Universal FFI lets you call **any** Python module dynamically, without
compile-time code generation. It's the "escape hatch" for:

- Libraries not in your generated wrappers
- Runtime-determined module paths
- Quick scripts and prototyping
- Stdlib modules not worth generating

## Quick Start

```elixir
# Call any Python function
{:ok, result} = SnakeBridge.call("math", "sqrt", [16])

# Get module attributes
{:ok, pi} = SnakeBridge.get("math", "pi")

# Work with Python objects
{:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp/file.txt"])
{:ok, name} = SnakeBridge.attr(path, "name")
{:ok, exists?} = SnakeBridge.method(path, "exists", [])

# Explicit bytes for crypto
{:ok, hash} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])
```

## Running the Example

```bash
cd examples/universal_ffi_example
mix deps.get
mix run -e "UniversalFfiExample.run_all()"
mix test
```

## APIs Demonstrated

| Function | Purpose |
|----------|---------|
| `SnakeBridge.call/4` | Call any Python function |
| `SnakeBridge.get/3` | Get module attributes |
| `SnakeBridge.stream/5` | Stream from generators |
| `SnakeBridge.method/4` | Call method on ref |
| `SnakeBridge.attr/3` | Get attribute from ref |
| `SnakeBridge.set_attr/4` | Set attribute on ref |
| `SnakeBridge.bytes/1` | Explicit binary encoding |
| `SnakeBridge.ref?/1` | Check if value is ref |
| `SnakeBridge.current_session/0` | Get session ID |
| `SnakeBridge.release_auto_session/0` | Clean up session |
```

---

## Test Specifications

Each updated/new example must pass:

```bash
cd examples/{example_name}
mix deps.get
mix compile --warnings-as-errors
mix test
mix run -e "{ExampleModule}.run_all()"
```

## Verification Checklist

- [ ] `dynamic_dispatch_example` - Updated with new convenience APIs
- [ ] `types_showcase` - Added Bytes and non-string key examples
- [ ] `session_lifecycle_example` - Added auto-session demonstration
- [ ] `universal_ffi_example` - NEW comprehensive showcase created
- [ ] All examples compile without warnings
- [ ] All example tests pass
- [ ] All `run_all()` functions execute successfully

## CHANGELOG Entry

Update `CHANGELOG.md` 0.8.4 entry:

```markdown
### Added
- New `universal_ffi_example` showcasing all Universal FFI features

### Changed
- Updated `dynamic_dispatch_example` with new convenience APIs
- Updated `types_showcase` with Bytes and non-string key examples
- Updated `session_lifecycle_example` with auto-session demonstration
```
