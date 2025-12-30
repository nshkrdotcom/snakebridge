# Implementation Prompt: Domain 1 - Core Type System & Marshalling

## Context

You are implementing critical fixes to SnakeBridge's type system to achieve "Universal FFI" status. This is a **P0 blocking** domain.

## Required Reading

Before implementing, read these files in order:

### Critique Documents
1. `docs/20251229/critique/001_gpt52.md` - Sections 4, 8 (atom decoding, boundary encoding)
2. `docs/20251229/critique/002_g3p.md` - Section 4 (zero-copy binary)
3. `docs/20251229/critique/003_g3p.md` - Section 1A (string fallacy)

### Implementation Plan
4. `docs/20251229/implementation/00_master_plan.md` - Domain 1 overview

### Source Files (Elixir)
5. `lib/snakebridge/types.ex` - Main type delegator
6. `lib/snakebridge/types/encoder.ex` - Elixir → Python encoding
7. `lib/snakebridge/types/decoder.ex` - Python → Elixir decoding
8. `lib/snakebridge/runtime.ex` - Runtime call functions
9. `lib/snakebridge/ref.ex` - Reference structure

### Source Files (Python)
10. `priv/python/snakebridge_types.py` - Python encoding/decoding (CRITICAL: lines 153-157, 220-224)
11. `priv/python/snakebridge_adapter.py` - Adapter with registry

### Test Files
12. `test/snakebridge/types/encoder_test.exs` - Existing encoder tests
13. `test/snakebridge/types/decoder_test.exs` - Existing decoder tests

## Issues to Fix

### Issue 1.1: Atom Decoding (P0)
**Problem**: Python decodes atoms to `Atom()` class objects, breaking libraries expecting strings.
**Location**: `priv/python/snakebridge_types.py` lines 220-224
**Fix**: Default atom decoding to return plain Python strings. Add config for opt-in `Atom` class.

### Issue 1.2: String Fallacy Fallback (P0)
**Problem**: Unknown Python types fall back to `str(value)`, losing method chaining capability.
**Location**: `priv/python/snakebridge_types.py` lines 153-157
**Fix**: Create auto-ref for unknown types instead of stringifying. Store in `_instance_registry`.

### Issue 1.3: Boundary Marshalling (P0)
**Problem**: `SnakeBridge.Runtime.call/4` doesn't auto-encode/decode at boundary.
**Location**: `lib/snakebridge/runtime.ex`
**Fix**: Wrap args with `SnakeBridge.Types.encode/1`, wrap result with `decode/1`.

### Issue 1.4: Ref Type Decoding (P1)
**Problem**: Decoder has no handler for `{"__type__": "ref"}`.
**Location**: `lib/snakebridge/types/decoder.ex`
**Fix**: Add decoder clause returning `SnakeBridge.Ref` struct.

## TDD Implementation Steps

### Step 1: Write Tests First

Create `test/snakebridge/types/auto_ref_test.exs`:
```elixir
defmodule SnakeBridge.Types.AutoRefTest do
  use ExUnit.Case, async: true

  describe "Python auto-ref for unknown types" do
    test "pandas DataFrame returns ref not string" do
      # This test requires integration with real Python
      # For unit test, verify decoder handles ref structure
      ref_data = %{
        "__type__" => "ref",
        "__schema__" => 1,
        "id" => "abc123",
        "session_id" => "default",
        "python_module" => "pandas",
        "library" => "pandas"
      }

      result = SnakeBridge.Types.decode(ref_data)
      assert is_map(result)
      assert result["__type__"] == "ref"
    end
  end
end
```

Create `test/snakebridge/types/atom_decoding_test.exs`:
```elixir
defmodule SnakeBridge.Types.AtomDecodingTest do
  use ExUnit.Case, async: true

  describe "atom encoding for Python" do
    test "atoms encode with tagged format" do
      encoded = SnakeBridge.Types.encode(:cuda)
      assert encoded["__type__"] == "atom"
      assert encoded["value"] == "cuda"
    end
  end
end
```

### Step 2: Run Tests (Expect Failures)
```bash
mix test test/snakebridge/types/auto_ref_test.exs
mix test test/snakebridge/types/atom_decoding_test.exs
```

### Step 3: Implement Fixes

#### 3.1 Fix Python Atom Decoding
File: `priv/python/snakebridge_types.py`

Change lines 220-224 from:
```python
if type_tag == "atom":
    return Atom(value.get("value", ""))
```

To:
```python
if type_tag == "atom":
    # Default: return plain string for library compatibility
    # Opt-in to Atom class via SNAKEBRIDGE_ATOM_CLASS=true
    atom_value = value.get("value", "")
    if os.environ.get("SNAKEBRIDGE_ATOM_CLASS", "").lower() in ("true", "1", "yes"):
        return Atom(atom_value)
    return atom_value
```

#### 3.2 Fix Python Auto-Ref Fallback
File: `priv/python/snakebridge_types.py`

Change lines 153-157 from:
```python
# For any other type, try to convert to string
try:
    return str(value)
except Exception:
    return f"<non-serializable: {type(value).__name__}>"
```

To:
```python
# For any other type, create auto-ref if in adapter context
# This is handled by encode_result() in snakebridge_adapter.py
# which wraps with context. Here we provide fallback.
try:
    # Check if this is a complex object that should be a ref
    if hasattr(value, '__class__') and not isinstance(value, (str, bytes, int, float, bool, type(None))):
        # Signal that this needs ref wrapping
        return {"__needs_ref__": True, "__type_name__": type(value).__name__}
    return str(value)
except Exception:
    return f"<non-serializable: {type(value).__name__}>"
```

Then in `priv/python/snakebridge_adapter.py`, update `encode_result()`:
```python
def encode_result(result, session_id, python_module, library):
    encoded = encode(result)
    # Check if encode signaled need for ref
    if isinstance(encoded, dict) and encoded.get("__needs_ref__"):
        return _make_ref(session_id, result, python_module, library)
    return encoded
```

#### 3.3 Add Boundary Marshalling
File: `lib/snakebridge/runtime.ex`

Add encoding wrapper in `call/4`:
```elixir
def call(module, function, args, opts \\ []) do
  {runtime_opts, kwargs} = normalize_args_opts([], opts)

  # Encode args at boundary
  encoded_args = Enum.map(args, &SnakeBridge.Types.encode/1)
  encoded_kwargs = encode_kwargs(kwargs)

  payload = base_payload(module, function, encoded_args, encoded_kwargs, false)

  result = execute_with_telemetry(metadata, fn ->
    runtime_client().execute("snakebridge.call", payload, runtime_opts)
  end)

  # Decode result at boundary
  case result do
    {:ok, value} -> {:ok, SnakeBridge.Types.decode(value)}
    error -> error
  end
end

defp encode_kwargs(kwargs) do
  kwargs
  |> Enum.into(%{}, fn {k, v} -> {to_string(k), SnakeBridge.Types.encode(v)} end)
end
```

#### 3.4 Add Ref Decoder
File: `lib/snakebridge/types/decoder.ex`

Add clause before the catch-all:
```elixir
def decode(%{"__type__" => "ref"} = ref) do
  # Return ref as-is, maintaining wire format for later use
  ref
end
```

### Step 4: Run Tests (Expect Pass)
```bash
mix test test/snakebridge/types/
mix test
```

### Step 5: Run Full Quality Checks
```bash
mix compile --warnings-as-errors
mix dialyzer
mix credo --strict
```

### Step 6: Update Examples

Add new example or update `examples/types_showcase/` to demonstrate:
- Passing atoms to Python (verify they work as strings)
- Receiving complex objects as refs
- Chaining method calls on returned refs

Update `examples/run_all.sh` if new example added.

### Step 7: Update Documentation

Update `README.md`:
- Document atom → string mapping behavior
- Document auto-ref for complex types
- Add configuration for `SNAKEBRIDGE_ATOM_CLASS`

## Acceptance Criteria

- [ ] Atoms passed to Python become strings by default
- [ ] Unknown Python types return refs, not strings
- [ ] Refs can be used for subsequent method calls
- [ ] Runtime automatically encodes/decodes at boundary
- [ ] All existing tests pass
- [ ] New tests for this domain pass
- [ ] No dialyzer errors
- [ ] No credo warnings
- [ ] Examples updated and passing

## Dependencies

This domain should be implemented **first** as it's a foundation for:
- Domain 5 (Reference Lifecycle) - auto-ref depends on this
- Domain 6 (Python Idioms) - generator refs depend on this
- Domain 7 (Protocol Integration) - ref handling depends on this
