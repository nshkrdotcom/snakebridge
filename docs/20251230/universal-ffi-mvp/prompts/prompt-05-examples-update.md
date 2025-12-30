# Prompt 05: Examples Update for Universal FFI

**Objective**: Update existing examples and create a new example to showcase Universal FFI features.

**Dependencies**: Prompts 01, 02, 03, and 04 must be completed first.

## Required Reading

Before starting, read these files completely:

### Documentation
- `docs/20251230/universal-ffi-mvp/00-overview.md` - Full context
- `docs/20251230/universal-ffi-mvp/08-examples-update.md` - Examples update spec

### Source Files (to understand what APIs are now available)
- `lib/snakebridge.ex` - Universal FFI public API
- `lib/snakebridge/runtime.ex` - Runtime implementation
- `lib/snakebridge/bytes.ex` - Bytes struct
- `lib/snakebridge/types/encoder.ex` - Encoder with tagged dict

### Existing Examples to Update
- `examples/dynamic_dispatch_example/lib/dynamic_dispatch_example.ex`
- `examples/dynamic_dispatch_example/test/dynamic_dispatch_example_test.exs`
- `examples/types_showcase/lib/types_showcase.ex`
- `examples/types_showcase/test/types_showcase_test.exs`
- `examples/session_lifecycle_example/lib/session_lifecycle_example.ex`
- `examples/session_lifecycle_example/test/session_lifecycle_example_test.exs`

## Implementation Tasks

### Task 1: Update `dynamic_dispatch_example`

This is the PRIMARY example for Universal FFI. It currently uses `Runtime.call_dynamic/4` and `Dynamic.*` APIs. Add the new convenience APIs.

**Path**: `examples/dynamic_dispatch_example/`

#### 1.1 Update `lib/dynamic_dispatch_example.ex`

Add new sections demonstrating v0.8.4 convenience APIs:

```elixir
# Add after existing demos

# ============================================================================
# New Universal FFI Convenience API (v0.8.4+)
# ============================================================================

@doc """
Demonstrates SnakeBridge.call/4 - the new convenience API.
This is the RECOMMENDED way to call Python functions dynamically.
"""
def demo_snakebridge_call do
  IO.puts("\n=== SnakeBridge.call/4 (NEW in v0.8.4) ===")

  # Simple function call
  {:ok, result} = SnakeBridge.call("math", "sqrt", [16])
  IO.puts("SnakeBridge.call(\"math\", \"sqrt\", [16]) = #{result}")

  # With kwargs
  {:ok, rounded} = SnakeBridge.call("builtins", "round", [3.14159], ndigits: 2)
  IO.puts("round(3.14159, ndigits=2) = #{rounded}")

  # Submodule
  {:ok, path} = SnakeBridge.call("os.path", "join", ["/tmp", "file.txt"])
  IO.puts("os.path.join(...) = #{path}")

  # Returns ref for objects
  {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
  IO.puts("Path ref: #{inspect(ref)}")

  {:ok, result}
end

@doc "Demonstrates SnakeBridge.get/3 for module attributes"
def demo_snakebridge_get do
  IO.puts("\n=== SnakeBridge.get/3 (NEW in v0.8.4) ===")

  {:ok, pi} = SnakeBridge.get("math", "pi")
  IO.puts("math.pi = #{pi}")

  {:ok, e} = SnakeBridge.get("math", :e)
  IO.puts("math.e = #{e}")

  {:ok, pi}
end

@doc "Demonstrates SnakeBridge.method/4, attr/3"
def demo_snakebridge_method_attr do
  IO.puts("\n=== SnakeBridge.method/4, attr/3 (NEW in v0.8.4) ===")

  {:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp/test.txt"])

  {:ok, exists?} = SnakeBridge.method(path, "exists", [])
  IO.puts("path.exists() = #{exists?}")

  {:ok, name} = SnakeBridge.attr(path, "name")
  IO.puts("path.name = #{name}")

  {:ok, name}
end

@doc "Demonstrates SnakeBridge.ref?/1"
def demo_ref_check do
  IO.puts("\n=== SnakeBridge.ref?/1 (NEW in v0.8.4) ===")

  {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
  {:ok, num} = SnakeBridge.call("math", "sqrt", [16])

  IO.puts("ref?(path) = #{SnakeBridge.ref?(ref)}")
  IO.puts("ref?(4.0) = #{SnakeBridge.ref?(num)}")

  :ok
end

@doc "API comparison: old vs new"
def demo_api_comparison do
  IO.puts("\n=== API Comparison ===")

  # OLD
  {:ok, r1} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [16])
  # NEW
  {:ok, r2} = SnakeBridge.call("math", "sqrt", [16])

  IO.puts("Runtime.call_dynamic: #{r1}")
  IO.puts("SnakeBridge.call:     #{r2}")
  IO.puts("Equal: #{r1 == r2}")

  :ok
end
```

Update `run_all/0` to include new demos.

#### 1.2 Update `test/dynamic_dispatch_example_test.exs`

Add tests for new APIs:

```elixir
describe "new Universal FFI convenience APIs (v0.8.4)" do
  test "SnakeBridge.call/4 with string module" do
    assert {:ok, 4.0} = SnakeBridge.call("math", "sqrt", [16])
  end

  test "SnakeBridge.call/4 with kwargs" do
    assert {:ok, 3.14} = SnakeBridge.call("builtins", "round", [3.14159], ndigits: 2)
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
    assert {:ok, "test.txt"} = SnakeBridge.attr(path, "name")
  end

  test "SnakeBridge.ref?/1 identifies refs" do
    {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
    assert SnakeBridge.ref?(ref)
    refute SnakeBridge.ref?("string")
  end

  test "bang variants work" do
    assert SnakeBridge.call!("math", "sqrt", [16]) == 4.0
  end
end
```

---

### Task 2: Update `types_showcase`

Add `SnakeBridge.Bytes` and non-string key map examples.

**Path**: `examples/types_showcase/`

#### 2.1 Update `lib/types_showcase.ex`

Add new type demonstrations:

```elixir
@doc """
Demonstrates SnakeBridge.Bytes for explicit binary encoding (v0.8.4).
"""
def demo_bytes do
  IO.puts("\n=== SnakeBridge.Bytes (NEW in v0.8.4) ===")

  # Hashlib requires bytes
  {:ok, hash_ref} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])
  {:ok, hex} = SnakeBridge.method(hash_ref, "hexdigest", [])
  IO.puts("md5(b\"abc\") = #{hex}")

  # Base64
  {:ok, encoded} = SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes("hello")])
  IO.puts("b64encode(b\"hello\") = #{inspect(encoded)}")

  # Binary round-trip
  original = <<0, 1, 2, 128, 255>>
  {:ok, b64} = SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes(original)])
  {:ok, decoded} = SnakeBridge.call("base64", "b64decode", [b64])
  IO.puts("Binary round-trip: #{original == decoded}")

  {:ok, hex}
end

@doc """
Demonstrates non-string key maps (v0.8.4 tagged dict format).
"""
def demo_non_string_key_maps do
  IO.puts("\n=== Non-String Key Maps (NEW in v0.8.4) ===")

  # Integer keys
  int_map = %{1 => "one", 2 => "two", 3 => "three"}
  {:ok, ref} = SnakeBridge.call("builtins", "dict", [int_map])
  {:ok, value} = SnakeBridge.method(ref, "get", [2])
  IO.puts("dict[2] = #{value}")

  # Tuple keys
  tuple_map = %{{0, 0} => "origin", {1, 1} => "diagonal"}
  {:ok, ref2} = SnakeBridge.call("builtins", "dict", [tuple_map])
  {:ok, origin} = SnakeBridge.method(ref2, "get", [{0, 0}])
  IO.puts("coords[(0,0)] = #{origin}")

  {:ok, value}
end
```

Update `run_all/0` to include new demos.

#### 2.2 Update `test/types_showcase_test.exs`

```elixir
describe "SnakeBridge.Bytes (v0.8.4)" do
  test "enables hashlib" do
    {:ok, ref} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])
    {:ok, hex} = SnakeBridge.method(ref, "hexdigest", [])
    assert hex == "900150983cd24fb0d6963f7d28e17f72"
  end

  test "binary round-trip" do
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

### Task 3: Update `session_lifecycle_example`

Add auto-session demonstration.

**Path**: `examples/session_lifecycle_example/`

#### 3.1 Update `lib/session_lifecycle_example.ex`

Add auto-session section:

```elixir
@doc """
Demonstrates auto-session feature (NEW in v0.8.4).
"""
def demo_auto_session do
  IO.puts("\n=== Auto-Session (NEW in v0.8.4) ===")

  # First call creates auto-session
  {:ok, _} = SnakeBridge.call("math", "sqrt", [16])
  session = SnakeBridge.current_session()
  IO.puts("Auto-session: #{session}")
  IO.puts("Starts with 'auto_': #{String.starts_with?(session, "auto_")}")

  # Subsequent calls reuse same session
  {:ok, _} = SnakeBridge.call("math", "sqrt", [25])
  same = SnakeBridge.current_session()
  IO.puts("Same session: #{session == same}")

  {:ok, session}
end

@doc "Demonstrates session release"
def demo_session_release do
  IO.puts("\n=== Session Release ===")

  {:ok, _} = SnakeBridge.call("math", "sqrt", [16])
  old = SnakeBridge.current_session()

  :ok = SnakeBridge.release_auto_session()

  {:ok, _} = SnakeBridge.call("math", "sqrt", [25])
  new = SnakeBridge.current_session()

  IO.puts("Old: #{old}")
  IO.puts("New: #{new}")
  IO.puts("Different: #{old != new}")

  :ok
end

@doc "Demonstrates process isolation"
def demo_process_isolation do
  IO.puts("\n=== Process Isolation ===")

  {:ok, _} = SnakeBridge.call("math", "sqrt", [16])
  main = SnakeBridge.current_session()

  task = Task.async(fn ->
    {:ok, _} = SnakeBridge.call("math", "sqrt", [25])
    SnakeBridge.current_session()
  end) |> Task.await()

  IO.puts("Main: #{main}")
  IO.puts("Task: #{task}")
  IO.puts("Isolated: #{main != task}")

  :ok
end
```

#### 3.2 Update tests

```elixir
describe "auto-session (v0.8.4)" do
  test "auto-session created on first call" do
    SnakeBridge.Runtime.clear_auto_session()
    {:ok, _} = SnakeBridge.call("math", "sqrt", [16])
    session = SnakeBridge.current_session()
    assert String.starts_with?(session, "auto_")
  end

  test "session reused for subsequent calls" do
    SnakeBridge.Runtime.clear_auto_session()
    {:ok, _} = SnakeBridge.call("math", "sqrt", [16])
    s1 = SnakeBridge.current_session()
    {:ok, _} = SnakeBridge.call("math", "sqrt", [25])
    s2 = SnakeBridge.current_session()
    assert s1 == s2
  end

  test "release creates new session" do
    SnakeBridge.Runtime.clear_auto_session()
    {:ok, _} = SnakeBridge.call("math", "sqrt", [16])
    old = SnakeBridge.current_session()
    SnakeBridge.release_auto_session()
    {:ok, _} = SnakeBridge.call("math", "sqrt", [25])
    new = SnakeBridge.current_session()
    assert old != new
  end
end
```

---

### Task 4: Create `universal_ffi_example` (NEW)

Create a NEW comprehensive example showcasing all Universal FFI features.

**Path**: `examples/universal_ffi_example/`

#### 4.1 Create directory structure

```
examples/universal_ffi_example/
├── mix.exs
├── lib/
│   └── universal_ffi_example.ex
├── test/
│   ├── test_helper.exs
│   └── universal_ffi_example_test.exs
└── README.md
```

#### 4.2 Create `mix.exs`

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
    [{:snakebridge, path: "../.."}]
  end
end
```

#### 4.3 Create `lib/universal_ffi_example.ex`

Create comprehensive example module with all Universal FFI demos:
- `demo_basic_calls/0` - `SnakeBridge.call/4`
- `demo_module_attributes/0` - `SnakeBridge.get/3`
- `demo_object_methods/0` - `SnakeBridge.method/4`, `attr/3`
- `demo_bytes/0` - `SnakeBridge.bytes/1`
- `demo_non_string_keys/0` - Tagged dict maps
- `demo_sessions/0` - Auto-session
- `demo_bang_variants/0` - `call!`, `get!`, `method!`, `attr!`
- `demo_streaming/0` - `SnakeBridge.stream/5`
- `demo_when_to_use/0` - Guidance text
- `run_all/0` - Execute all demos

(See 08-examples-update.md for full implementation)

#### 4.4 Create `test/universal_ffi_example_test.exs`

Full test coverage for all APIs.

#### 4.5 Create `test/test_helper.exs`

```elixir
ExUnit.start()
```

#### 4.6 Create `README.md`

Document the example and how to run it.

---

## Verification Checklist

After implementation, verify each example:

```bash
# dynamic_dispatch_example
cd examples/dynamic_dispatch_example
mix deps.get
mix compile --warnings-as-errors
mix test
mix run -e "DynamicDispatchExample.run_all()"

# types_showcase
cd examples/types_showcase
mix deps.get
mix compile --warnings-as-errors
mix test
mix run -e "TypesShowcase.run_all()"

# session_lifecycle_example
cd examples/session_lifecycle_example
mix deps.get
mix compile --warnings-as-errors
mix test
mix run -e "SessionLifecycleExample.run_all()"

# universal_ffi_example (NEW)
cd examples/universal_ffi_example
mix deps.get
mix compile --warnings-as-errors
mix test
mix run -e "UniversalFfiExample.run_all()"
```

All must pass:
- ✅ Compiles without warnings
- ✅ All tests pass
- ✅ `run_all()` executes successfully

## CHANGELOG Entry

Update `CHANGELOG.md` 0.8.4 entry:

```markdown
### Added
- New `universal_ffi_example` showcasing all Universal FFI features

### Changed
- Updated `dynamic_dispatch_example` with new convenience APIs (`SnakeBridge.call/4`, etc.)
- Updated `types_showcase` with `SnakeBridge.Bytes` and non-string key map examples
- Updated `session_lifecycle_example` with auto-session demonstration
```

## Notes

- All new example code should follow existing example patterns
- Each demo function should print clear output explaining what it demonstrates
- Tests should be self-contained (clear auto-session in setup if needed)
- The `universal_ffi_example` is the canonical reference for Universal FFI usage
- Examples serve dual purpose: documentation AND integration tests
