# Prompt 04: Python Adapter Ref Safety

**Objective**: Harden Python adapter to always ref-wrap non-JSON-serializable values.

**Dependencies**: Prompts 01, 02, and 03 must be completed first.

## Required Reading

Before starting, read these files completely:

### Documentation
- `docs/20251230/universal-ffi-mvp/00-overview.md` - Full context
- `docs/20251230/universal-ffi-mvp/06-python-ref-safety.md` - Python ref safety spec

### Source Files
- `priv/python/snakebridge_types.py` - Python type encoding/decoding
- `priv/python/snakebridge_adapter.py` - Python adapter

## Problem Summary

The universal FFI requires: "if Python returns something non-JSON-serializable, SnakeBridge returns a ref."

This must be true for ALL non-serializable objects:
- NumPy arrays, Pandas DataFrames
- Custom class instances
- File handles, sockets
- Any object without JSON representation

Current risks:
1. Heuristic encoding paths may partially serialize objects
2. Lossy placeholders may be returned
3. Silent failures when encoding fails

## Implementation Tasks

### Task 1: Update snakebridge_types.py encode()

Modify `priv/python/snakebridge_types.py`:

1. Ensure clear fallback to `__needs_ref__`:

```python
import math
import base64
import datetime

# Supported types for direct JSON encoding
JSON_SAFE_PRIMITIVES = (type(None), bool, int, float, str)


def encode(value):
    """
    Encode a Python value for transmission to Elixir.

    Returns one of:
    - JSON-safe primitive (None, bool, int, float, str)
    - JSON-safe list (recursively encoded)
    - JSON-safe dict with string keys (recursively encoded)
    - Tagged value with __type__ key
    - Marker dict with __needs_ref__ = True (for ref-wrapping)
    - Marker dict with __needs_stream_ref__ = True (for iterators)

    NEVER returns partially-encoded or lossy representations.
    """
    # None
    if value is None:
        return None

    # Booleans (must check before int - bool is subclass of int)
    if isinstance(value, bool):
        return value

    # Integers
    if isinstance(value, int):
        return value

    # Floats (with special value handling)
    if isinstance(value, float):
        return _encode_float(value)

    # Strings
    if isinstance(value, str):
        return value

    # Bytes/bytearray - always tagged
    if isinstance(value, (bytes, bytearray)):
        return {
            "__type__": "bytes",
            "__schema__": 1,
            "data": base64.b64encode(value).decode("ascii")
        }

    # Tuples - tagged
    if isinstance(value, tuple):
        return _encode_tuple(value)

    # Sets/frozensets - tagged
    if isinstance(value, frozenset):
        return _encode_frozenset(value)
    if isinstance(value, set):
        return _encode_set(value)

    # Complex numbers - tagged
    if isinstance(value, complex):
        return {
            "__type__": "complex",
            "__schema__": 1,
            "real": value.real,
            "imag": value.imag
        }

    # Datetime types - tagged
    if isinstance(value, datetime.datetime):
        return {
            "__type__": "datetime",
            "__schema__": 1,
            "value": value.isoformat()
        }
    if isinstance(value, datetime.date):
        return {
            "__type__": "date",
            "__schema__": 1,
            "value": value.isoformat()
        }
    if isinstance(value, datetime.time):
        return {
            "__type__": "time",
            "__schema__": 1,
            "value": value.isoformat()
        }

    # Lists - recursively encode
    if isinstance(value, list):
        return _encode_list(value)

    # Dicts - handle carefully
    if isinstance(value, dict):
        return _encode_dict(value)

    # Generators and iterators - need stream ref
    if _is_generator_or_iterator(value):
        return {
            "__needs_stream_ref__": True,
            "__stream_type__": _get_stream_type(value),
            "__type_name__": type(value).__name__,
            "__module__": type(value).__module__
        }

    # EVERYTHING ELSE - needs a ref
    # This is the critical safety net
    return {
        "__needs_ref__": True,
        "__type_name__": type(value).__name__,
        "__module__": type(value).__module__
    }


def _encode_float(value):
    """Encode a float, handling special values."""
    if math.isinf(value):
        return {
            "__type__": "special_float",
            "__schema__": 1,
            "value": "infinity" if value > 0 else "neg_infinity"
        }
    if math.isnan(value):
        return {
            "__type__": "special_float",
            "__schema__": 1,
            "value": "nan"
        }
    return value


def _encode_tuple(value):
    """Encode a tuple, checking for unencodable items."""
    elements = []
    for item in value:
        enc = encode(item)
        if isinstance(enc, dict) and enc.get("__needs_ref__"):
            # Item needs ref - whole tuple needs ref
            return {
                "__needs_ref__": True,
                "__type_name__": "tuple",
                "__module__": "builtins",
                "__reason__": f"contains unencodable item of type {enc.get('__type_name__')}"
            }
        elements.append(enc)
    return {
        "__type__": "tuple",
        "__schema__": 1,
        "elements": elements
    }


def _encode_set(value):
    """Encode a set."""
    elements = []
    for item in value:
        enc = encode(item)
        if isinstance(enc, dict) and enc.get("__needs_ref__"):
            return {
                "__needs_ref__": True,
                "__type_name__": "set",
                "__module__": "builtins"
            }
        elements.append(enc)
    return {
        "__type__": "set",
        "__schema__": 1,
        "elements": elements
    }


def _encode_frozenset(value):
    """Encode a frozenset."""
    elements = []
    for item in value:
        enc = encode(item)
        if isinstance(enc, dict) and enc.get("__needs_ref__"):
            return {
                "__needs_ref__": True,
                "__type_name__": "frozenset",
                "__module__": "builtins"
            }
        elements.append(enc)
    return {
        "__type__": "frozenset",
        "__schema__": 1,
        "elements": elements
    }


def _encode_list(lst):
    """Encode a list, checking for unencodable items."""
    encoded = []
    for item in lst:
        enc = encode(item)
        if isinstance(enc, dict) and enc.get("__needs_ref__"):
            # Item can't be encoded - whole list needs ref
            return {
                "__needs_ref__": True,
                "__type_name__": "list",
                "__module__": "builtins",
                "__reason__": f"contains unencodable item of type {enc.get('__type_name__')}"
            }
        encoded.append(enc)
    return encoded


def _encode_dict(d):
    """Encode a dictionary."""
    if not d:
        return {}

    all_string_keys = all(isinstance(k, str) for k in d.keys())

    if all_string_keys:
        return _encode_string_key_dict(d)
    else:
        return _encode_tagged_dict(d)


def _encode_string_key_dict(d):
    """Encode a dict with all string keys."""
    encoded = {}
    for k, v in d.items():
        enc_v = encode(v)
        if isinstance(enc_v, dict) and enc_v.get("__needs_ref__"):
            # Value can't be encoded - whole dict needs ref
            return {
                "__needs_ref__": True,
                "__type_name__": "dict",
                "__module__": "builtins",
                "__reason__": f"contains unencodable value for key '{k}'"
            }
        encoded[k] = enc_v
    return encoded


def _encode_tagged_dict(d):
    """Encode a dict with non-string keys as tagged format."""
    pairs = []
    for k, v in d.items():
        enc_k = encode(k)
        enc_v = encode(v)

        if isinstance(enc_k, dict) and enc_k.get("__needs_ref__"):
            return {
                "__needs_ref__": True,
                "__type_name__": "dict",
                "__module__": "builtins",
                "__reason__": "contains unencodable key"
            }
        if isinstance(enc_v, dict) and enc_v.get("__needs_ref__"):
            return {
                "__needs_ref__": True,
                "__type_name__": "dict",
                "__module__": "builtins",
                "__reason__": "contains unencodable value"
            }

        pairs.append([enc_k, enc_v])

    return {
        "__type__": "dict",
        "__schema__": 1,
        "pairs": pairs
    }


def _is_generator_or_iterator(value):
    """Check if value is a generator or iterator."""
    import types
    if isinstance(value, (types.GeneratorType,)):
        return True
    # Check for async generators if available
    if hasattr(types, 'AsyncGeneratorType') and isinstance(value, types.AsyncGeneratorType):
        return True
    # Check for iterator protocol
    if hasattr(value, '__next__') and hasattr(value, '__iter__'):
        # Exclude basic iterable types
        if not isinstance(value, (str, bytes, list, tuple, dict, set, frozenset)):
            return True
    return False


def _get_stream_type(value):
    """Determine stream type for iterator/generator."""
    import types
    if isinstance(value, types.GeneratorType):
        return "generator"
    if hasattr(types, 'AsyncGeneratorType') and isinstance(value, types.AsyncGeneratorType):
        return "async_generator"
    return "iterator"
```

2. Add tagged dict decoding:

```python
def decode(value, session_id=None, context=None):
    """Decode an Elixir-encoded value to Python."""
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return [decode(item, session_id, context) for item in value]

    if isinstance(value, dict):
        type_tag = value.get("__type__")

        if type_tag == "dict":
            return _decode_tagged_dict(value, session_id, context)

        # ... other type handlers ...

        # Plain dict (no __type__)
        return {k: decode(v, session_id, context) for k, v in value.items()}

    return value


def _decode_tagged_dict(value, session_id=None, context=None):
    """Decode a tagged dict with potentially non-string keys."""
    pairs = value.get("pairs", [])
    result = {}
    for pair in pairs:
        if isinstance(pair, list) and len(pair) == 2:
            key = decode(pair[0], session_id, context)
            val = decode(pair[1], session_id, context)
            result[key] = val
    return result
```

### Task 2: Update snakebridge_adapter.py encode_result()

Modify `priv/python/snakebridge_adapter.py`:

```python
def encode_result(result, session_id, python_module, library):
    """
    Encode a Python result for transmission to Elixir.

    INVARIANT: The returned value is ALWAYS one of:
    1. A JSON-safe primitive (None, bool, int, float, str)
    2. A JSON-safe list/dict (recursively safe)
    3. A tagged value with __type__ that Elixir can decode
    4. A ref for non-serializable objects
    5. A stream_ref for iterators

    NEVER returns partially encoded or lossy data.
    """
    from snakebridge_types import encode

    encoded = encode(result)

    # Stream ref request
    if isinstance(encoded, dict) and encoded.get("__needs_stream_ref__"):
        stream_type = encoded.get("__stream_type__", "iterator")
        return _make_stream_ref(session_id, result, python_module, library, stream_type)

    # Ref request
    if isinstance(encoded, dict) and encoded.get("__needs_ref__"):
        return _make_ref(session_id, result, python_module, library)

    # Validate result is JSON-safe (safety check)
    if not _is_json_safe(encoded):
        import sys
        print(f"[SnakeBridge WARNING] encode() returned non-JSON-safe: {type(result)}, wrapping in ref",
              file=sys.stderr)
        return _make_ref(session_id, result, python_module, library)

    return encoded


def _is_json_safe(value):
    """
    Verify a value is safe to serialize as JSON.

    Safety check after encoding - if encode() is correct, this should always be True.
    """
    import math

    if value is None:
        return True
    if isinstance(value, bool):
        return True
    if isinstance(value, (int, float)):
        if isinstance(value, float) and (math.isinf(value) or math.isnan(value)):
            return False
        return True
    if isinstance(value, str):
        return True
    if isinstance(value, list):
        return all(_is_json_safe(item) for item in value)
    if isinstance(value, dict):
        # Check for valid tagged types
        type_tag = value.get("__type__")
        if type_tag in ("bytes", "tuple", "set", "frozenset", "complex",
                        "datetime", "date", "time", "special_float",
                        "atom", "dict", "ref", "stream_ref", "callback"):
            # Tagged values are safe
            return all(_is_json_safe(v) for v in value.values())
        # Regular dict - keys must be strings
        if not all(isinstance(k, str) for k in value.keys()):
            return False
        return all(_is_json_safe(v) for v in value.values())
    return False
```

### Task 3: Ensure All Call Handlers Use encode_result()

Review and update all call handlers in `snakebridge_adapter.py`:

```python
def _handle_dynamic_call(arguments, session_id):
    """Handle dynamic function call."""
    module_path = arguments.get("module_path") or arguments.get("python_module")
    function_name = arguments.get("function")
    args = arguments.get("args", [])
    kwargs = arguments.get("kwargs", {})

    decoded_args = [decode(arg, session_id) for arg in args]
    decoded_kwargs = {k: decode(v, session_id) for k, v in kwargs.items()}

    module = _import_module(module_path)
    func = getattr(module, function_name)
    result = func(*decoded_args, **decoded_kwargs)

    # ALWAYS use encode_result
    library = _library_from_module_path(module_path)
    return encode_result(result, session_id, module_path, library)


def _handle_method_call(arguments, session_id):
    """Handle method call on a ref."""
    ref_data = arguments.get("ref")
    method_name = arguments.get("function") or arguments.get("method")
    args = arguments.get("args", [])
    kwargs = arguments.get("kwargs", {})

    instance = _resolve_ref(ref_data, session_id)
    decoded_args = [decode(arg, session_id) for arg in args]
    decoded_kwargs = {k: decode(v, session_id) for k, v in kwargs.items()}

    method = getattr(instance, method_name)
    result = method(*decoded_args, **decoded_kwargs)

    # ALWAYS use encode_result
    python_module = ref_data.get("python_module", "unknown")
    library = ref_data.get("library", "unknown")
    return encode_result(result, session_id, python_module, library)


def _handle_get_attr(arguments, session_id):
    """Handle attribute get on a ref."""
    ref_data = arguments.get("ref")
    attr_name = arguments.get("attr")

    instance = _resolve_ref(ref_data, session_id)
    result = getattr(instance, attr_name)

    # ALWAYS use encode_result
    python_module = ref_data.get("python_module", "unknown")
    library = ref_data.get("library", "unknown")
    return encode_result(result, session_id, python_module, library)


def _handle_class_call(arguments, session_id):
    """Handle class instantiation."""
    module_path = arguments.get("module_path") or arguments.get("python_module")
    class_name = arguments.get("class") or arguments.get("function")
    args = arguments.get("args", [])
    kwargs = arguments.get("kwargs", {})

    decoded_args = [decode(arg, session_id) for arg in args]
    decoded_kwargs = {k: decode(v, session_id) for k, v in kwargs.items()}

    module = _import_module(module_path)
    cls = getattr(module, class_name)
    instance = cls(*decoded_args, **decoded_kwargs)

    # Class instances ALWAYS need refs
    library = _library_from_module_path(module_path)
    return _make_ref(session_id, instance, module_path, library)


def _handle_module_attr(arguments, session_id):
    """Handle module attribute get."""
    python_module = arguments.get("python_module")
    attr_name = arguments.get("attr")

    module = _import_module(python_module)
    result = getattr(module, attr_name)

    # Use encode_result for consistent handling
    library = _library_from_module_path(python_module)
    return encode_result(result, session_id, python_module, library)
```

### Task 4: Write Python Tests

Create/update `test/python/test_snakebridge_types.py`:

```python
import pytest
from snakebridge_types import encode, _is_json_safe


class TestEncodeRefSafety:
    """Test that non-JSON-safe values result in __needs_ref__."""

    def test_custom_class_needs_ref(self):
        class MyClass:
            pass
        result = encode(MyClass())
        assert result.get("__needs_ref__") is True

    def test_lambda_needs_ref(self):
        fn = lambda x: x + 1
        result = encode(fn)
        assert result.get("__needs_ref__") is True

    def test_generator_needs_stream_ref(self):
        gen = (x for x in range(10))
        result = encode(gen)
        assert result.get("__needs_stream_ref__") is True

    def test_list_with_unencodable_needs_ref(self):
        class MyClass:
            pass
        lst = [1, 2, MyClass(), 4]
        result = encode(lst)
        assert result.get("__needs_ref__") is True

    def test_dict_with_unencodable_value_needs_ref(self):
        class MyClass:
            pass
        d = {"key": MyClass()}
        result = encode(d)
        assert result.get("__needs_ref__") is True


class TestEncodeSafeValues:
    def test_primitives(self):
        assert encode(None) is None
        assert encode(True) is True
        assert encode(False) is False
        assert encode(42) == 42
        assert encode(3.14) == 3.14
        assert encode("hello") == "hello"

    def test_list_of_primitives(self):
        assert encode([1, 2, 3]) == [1, 2, 3]

    def test_dict_string_keys(self):
        assert encode({"a": 1}) == {"a": 1}


class TestTaggedDict:
    def test_int_keys(self):
        result = encode({1: "one", 2: "two"})
        assert result.get("__type__") == "dict"
        assert "pairs" in result

    def test_tuple_keys(self):
        result = encode({(0, 0): "origin"})
        assert result.get("__type__") == "dict"


class TestIsJsonSafe:
    def test_primitives_safe(self):
        assert _is_json_safe(None)
        assert _is_json_safe(True)
        assert _is_json_safe(42)
        assert _is_json_safe("hello")

    def test_inf_not_safe(self):
        assert not _is_json_safe(float('inf'))

    def test_nan_not_safe(self):
        assert not _is_json_safe(float('nan'))
```

### Task 5: Write Elixir Integration Tests

Create `test/snakebridge/python_ref_safety_integration_test.exs`:

```elixir
defmodule SnakeBridge.PythonRefSafetyIntegrationTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  describe "non-JSON values return refs" do
    test "pathlib.Path returns ref" do
      {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
      assert %SnakeBridge.Ref{} = ref
    end

    test "file handle returns ref" do
      {:ok, ref} = SnakeBridge.call("builtins", "open", ["/dev/null", "r"])
      assert %SnakeBridge.Ref{} = ref
      # Clean up
      SnakeBridge.method(ref, "close", [])
    end
  end

  describe "JSON-safe values pass through" do
    test "int returns int" do
      {:ok, result} = SnakeBridge.call("builtins", "int", ["42"])
      assert result == 42
    end

    test "str returns str" do
      {:ok, result} = SnakeBridge.call("builtins", "str", [42])
      assert result == "42"
    end

    test "list returns list" do
      {:ok, result} = SnakeBridge.call("builtins", "list", [[1, 2, 3]])
      assert result == [1, 2, 3]
    end

    test "dict returns dict" do
      {:ok, result} = SnakeBridge.call("builtins", "dict", [[["a", 1], ["b", 2]]])
      assert result == %{"a" => 1, "b" => 2}
    end
  end
end
```

## Verification Checklist

Run after implementation:

```bash
# Run Python tests
cd priv/python && python -m pytest test_snakebridge_types.py -v

# Run Elixir tests
mix test test/snakebridge/python_ref_safety_integration_test.exs
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
### Changed
- Python adapter now unconditionally ref-wraps non-JSON-serializable return values
- Improved Python encode() to explicitly mark unencodable values with `__needs_ref__`
- Added JSON safety validation in encode_result() as a safety net

### Fixed
- Lists/dicts containing non-serializable items now properly return refs
- Eliminated partial/lossy encoding of complex Python objects
```

## Notes

- The `__needs_ref__` marker is a signal, not a final encoding
- `encode_result()` handles the marker and creates actual refs
- The `_is_json_safe()` check is a safety net - should rarely trigger if `encode()` is correct
- All call handlers must use `encode_result()` for consistency
- This is the final piece that makes the universal FFI reliable
