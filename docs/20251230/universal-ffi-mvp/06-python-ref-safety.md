# Fix #6: Python Adapter Ref Safety

**Status**: Specification
**Priority**: High
**Complexity**: Medium
**Estimated Changes**: ~100 lines Python

## Problem Statement

The universal FFI story hinges on: "if Python returns something non-JSON-serializable, SnakeBridge returns a ref."

This must be true for **everything**:
- C-extension objects (numpy arrays, torch tensors)
- Custom class instances
- Exceptions as objects
- Iterators and generators
- File handles and sockets
- Database connections
- Any object without a JSON representation

The current implementation has `_make_ref` + `_instance_registry` + `encode_result`, but there are risks:
1. **Heuristic encoding paths** that attempt partial serialization
2. **Lossy placeholders** for complex objects
3. **Silent failures** when encoding fails

## Solution

Ensure this invariant in the Python adapter:

> If `encode(result)` is not a plain JSON scalar/list/object-with-string-keys **or** contains an unrecognized tagged value → return a ref.

Never attempt "best effort" conversion for arbitrary objects.

## Implementation Details

### File: `priv/python/snakebridge_types.py`

#### Update `encode()` to be explicit about supported types

```python
# Supported primitive types for direct JSON encoding
JSON_SAFE_TYPES = (type(None), bool, int, float, str)

def encode(value):
    """
    Encode a Python value for transmission to Elixir.

    Returns one of:
    - JSON-safe primitive (None, bool, int, float, str)
    - JSON-safe list (recursively encoded)
    - JSON-safe dict with string keys (recursively encoded)
    - Tagged value with __type__ key
    - Marker dict with __needs_ref__ = True (for objects that need ref-wrapping)
    - Marker dict with __needs_stream_ref__ = True (for iterators/generators)

    NEVER returns partially-encoded or lossy representations.
    """
    # Primitives - direct pass-through
    if value is None:
        return None
    if isinstance(value, bool):  # Must check before int (bool is subclass of int)
        return value
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return _encode_float(value)
    if isinstance(value, str):
        return value

    # Bytes - always tagged
    if isinstance(value, (bytes, bytearray)):
        return {
            "__type__": "bytes",
            "__schema__": 1,
            "data": base64.b64encode(value).decode("ascii")
        }

    # Tuples - tagged
    if isinstance(value, tuple):
        return {
            "__type__": "tuple",
            "__schema__": 1,
            "elements": [encode(item) for item in value]
        }

    # Sets and frozensets - tagged
    if isinstance(value, frozenset):
        return {
            "__type__": "frozenset",
            "__schema__": 1,
            "elements": [encode(item) for item in value]
        }
    if isinstance(value, set):
        return {
            "__type__": "set",
            "__schema__": 1,
            "elements": [encode(item) for item in value]
        }

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

    # Lists - recursively encode, but check for unencodable items
    if isinstance(value, list):
        return _encode_list(value)

    # Dicts - handle carefully (may need tagged format)
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


def _encode_list(lst):
    """
    Encode a list, checking if any item needs ref-wrapping.

    If any item is unencodable (needs ref), the whole list needs ref-wrapping.
    """
    encoded = []
    for item in lst:
        enc = encode(item)
        if isinstance(enc, dict) and enc.get("__needs_ref__"):
            # Item can't be encoded - whole list needs ref-wrapping
            return {
                "__needs_ref__": True,
                "__type_name__": "list",
                "__module__": "builtins",
                "__reason__": f"contains unencodable item of type {enc.get('__type_name__')}"
            }
        encoded.append(enc)
    return encoded


def _encode_dict(d):
    """
    Encode a dictionary.

    - If all keys are strings and all values are encodable: plain dict
    - If keys are not all strings: tagged dict with pairs
    - If any value is unencodable: needs ref
    """
    if not d:
        return {}

    all_string_keys = all(isinstance(k, str) for k in d.keys())

    if all_string_keys:
        # Try to encode as plain dict
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
    else:
        # Non-string keys - use tagged dict format
        return _encode_tagged_dict(d)


def _encode_tagged_dict(d):
    """Encode a dict with non-string keys as tagged format."""
    pairs = []
    for k, v in d.items():
        enc_k = encode(k)
        enc_v = encode(v)

        # If key or value needs ref, whole dict needs ref
        if isinstance(enc_k, dict) and enc_k.get("__needs_ref__"):
            return {
                "__needs_ref__": True,
                "__type_name__": "dict",
                "__module__": "builtins",
                "__reason__": f"contains unencodable key"
            }
        if isinstance(enc_v, dict) and enc_v.get("__needs_ref__"):
            return {
                "__needs_ref__": True,
                "__type_name__": "dict",
                "__module__": "builtins",
                "__reason__": f"contains unencodable value"
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
    if isinstance(value, (types.GeneratorType, types.AsyncGeneratorType)):
        return True
    # Check for iterator protocol (has __next__ but isn't a basic type)
    if hasattr(value, '__next__') and hasattr(value, '__iter__'):
        if not isinstance(value, (str, bytes, list, tuple, dict, set, frozenset)):
            return True
    return False


def _get_stream_type(value):
    """Determine stream type for iterator/generator."""
    import types
    if isinstance(value, types.GeneratorType):
        return "generator"
    if isinstance(value, types.AsyncGeneratorType):
        return "async_generator"
    return "iterator"
```

### File: `priv/python/snakebridge_adapter.py`

#### Update `encode_result()` to enforce ref-wrapping

```python
def encode_result(result, session_id, python_module, library):
    """
    Encode a Python result for transmission to Elixir.

    INVARIANT: The returned value is ALWAYS one of:
    1. A JSON-safe primitive (None, bool, int, float, str)
    2. A JSON-safe list/dict (recursively safe)
    3. A tagged value with __type__ that Elixir can decode
    4. A ref ({"__type__": "ref", ...}) for non-serializable objects
    5. A stream_ref ({"__type__": "stream_ref", ...}) for iterators

    NEVER returns partially encoded or lossy data.
    """
    encoded = encode(result)

    # Stream ref request - create stream ref
    if isinstance(encoded, dict) and encoded.get("__needs_stream_ref__"):
        stream_type = encoded.get("__stream_type__", "iterator")
        return _make_stream_ref(session_id, result, python_module, library, stream_type)

    # Ref request - create ref
    if isinstance(encoded, dict) and encoded.get("__needs_ref__"):
        return _make_ref(session_id, result, python_module, library)

    # Validate result is actually JSON-safe
    if not _is_json_safe(encoded):
        # Safety net - this shouldn't happen if encode() is correct
        # but ensures we never send garbage
        _log_warning(f"encode() returned non-JSON-safe result: {type(encoded)}, wrapping in ref")
        return _make_ref(session_id, result, python_module, library)

    return encoded


def _is_json_safe(value):
    """
    Verify a value is safe to serialize as JSON.

    This is a safety check after encoding - if encode() is correct,
    this should always return True.
    """
    if value is None:
        return True
    if isinstance(value, bool):
        return True
    if isinstance(value, (int, float)):
        # Check for non-JSON floats (should be tagged already)
        if isinstance(value, float) and (math.isinf(value) or math.isnan(value)):
            return False
        return True
    if isinstance(value, str):
        return True
    if isinstance(value, list):
        return all(_is_json_safe(item) for item in value)
    if isinstance(value, dict):
        # Keys must be strings for JSON
        if not all(isinstance(k, str) for k in value.keys()):
            # Unless it's a tagged dict
            if value.get("__type__") != "dict":
                return False
        return all(_is_json_safe(v) for v in value.values())
    return False


def _log_warning(message):
    """Log a warning message."""
    import sys
    print(f"[SnakeBridge WARNING] {message}", file=sys.stderr)
```

#### Update call handlers to use `encode_result()`

Ensure all return paths go through `encode_result()`:

```python
def _handle_dynamic_call(arguments, session_id):
    """Handle dynamic function call."""
    module_path = arguments.get("module_path") or arguments.get("python_module")
    function_name = arguments.get("function")
    args = arguments.get("args", [])
    kwargs = arguments.get("kwargs", {})

    # Decode arguments
    decoded_args = [decode(arg, session_id) for arg in args]
    decoded_kwargs = {k: decode(v, session_id) for k, v in kwargs.items()}

    # Import and call
    module = _import_module(module_path)
    func = getattr(module, function_name)
    result = func(*decoded_args, **decoded_kwargs)

    # ALWAYS encode result - this ensures ref-wrapping
    library = _library_from_module_path(module_path)
    return encode_result(result, session_id, module_path, library)


def _handle_method_call(arguments, session_id):
    """Handle method call on a ref."""
    ref_data = arguments.get("ref")
    method_name = arguments.get("function") or arguments.get("method")
    args = arguments.get("args", [])
    kwargs = arguments.get("kwargs", {})

    # Resolve ref
    instance = _resolve_ref(ref_data, session_id)

    # Decode arguments
    decoded_args = [decode(arg, session_id) for arg in args]
    decoded_kwargs = {k: decode(v, session_id) for k, v in kwargs.items()}

    # Call method
    method = getattr(instance, method_name)
    result = method(*decoded_args, **decoded_kwargs)

    # ALWAYS encode result
    python_module = ref_data.get("python_module", "unknown")
    library = ref_data.get("library", "unknown")
    return encode_result(result, session_id, python_module, library)


def _handle_get_attr(arguments, session_id):
    """Handle attribute get on a ref."""
    ref_data = arguments.get("ref")
    attr_name = arguments.get("attr")

    instance = _resolve_ref(ref_data, session_id)
    result = getattr(instance, attr_name)

    # ALWAYS encode result - attribute values might be complex objects
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

    # Class instances ALWAYS need refs (they're not JSON-serializable)
    library = _library_from_module_path(module_path)
    return _make_ref(session_id, instance, module_path, library)
```

## Test Specifications

### File: `test/python/test_snakebridge_types.py` (NEW or additions)

```python
import pytest
import numpy as np
from snakebridge_types import encode, _is_json_safe


class TestEncodeRefSafety:
    """Test that non-JSON-safe values result in __needs_ref__."""

    def test_numpy_array_needs_ref(self):
        arr = np.array([1, 2, 3])
        result = encode(arr)
        assert result.get("__needs_ref__") is True
        assert result.get("__type_name__") == "ndarray"

    def test_custom_class_needs_ref(self):
        class MyClass:
            pass
        obj = MyClass()
        result = encode(obj)
        assert result.get("__needs_ref__") is True

    def test_file_handle_needs_ref(self):
        import tempfile
        with tempfile.NamedTemporaryFile() as f:
            result = encode(f)
            assert result.get("__needs_ref__") is True

    def test_lambda_needs_ref(self):
        fn = lambda x: x + 1
        result = encode(fn)
        assert result.get("__needs_ref__") is True

    def test_generator_needs_stream_ref(self):
        gen = (x for x in range(10))
        result = encode(gen)
        assert result.get("__needs_stream_ref__") is True
        assert result.get("__stream_type__") == "generator"

    def test_iterator_needs_stream_ref(self):
        it = iter([1, 2, 3])
        result = encode(it)
        assert result.get("__needs_stream_ref__") is True

    def test_list_with_unencodable_needs_ref(self):
        class MyClass:
            pass
        lst = [1, 2, MyClass(), 4]
        result = encode(lst)
        assert result.get("__needs_ref__") is True
        assert "contains unencodable item" in result.get("__reason__", "")

    def test_dict_with_unencodable_value_needs_ref(self):
        class MyClass:
            pass
        d = {"key": MyClass()}
        result = encode(d)
        assert result.get("__needs_ref__") is True


class TestEncodeSafeValues:
    """Test that JSON-safe values encode correctly."""

    def test_primitives(self):
        assert encode(None) is None
        assert encode(True) is True
        assert encode(False) is False
        assert encode(42) == 42
        assert encode(3.14) == 3.14
        assert encode("hello") == "hello"

    def test_list_of_primitives(self):
        result = encode([1, 2, 3])
        assert result == [1, 2, 3]

    def test_dict_string_keys(self):
        result = encode({"a": 1, "b": 2})
        assert result == {"a": 1, "b": 2}

    def test_nested_safe_structures(self):
        result = encode({"list": [1, 2], "nested": {"key": "value"}})
        assert result == {"list": [1, 2], "nested": {"key": "value"}}


class TestTaggedDict:
    """Test tagged dict encoding for non-string keys."""

    def test_int_keys(self):
        result = encode({1: "one", 2: "two"})
        assert result.get("__type__") == "dict"
        assert "pairs" in result

    def test_tuple_keys(self):
        result = encode({(0, 0): "origin"})
        assert result.get("__type__") == "dict"
        pairs = result.get("pairs")
        assert len(pairs) == 1
        # Key should be encoded tuple
        assert pairs[0][0].get("__type__") == "tuple"

    def test_mixed_keys(self):
        result = encode({"string": 1, 2: "int_key"})
        assert result.get("__type__") == "dict"


class TestIsJsonSafe:
    """Test the JSON safety checker."""

    def test_primitives_are_safe(self):
        assert _is_json_safe(None)
        assert _is_json_safe(True)
        assert _is_json_safe(42)
        assert _is_json_safe(3.14)
        assert _is_json_safe("hello")

    def test_inf_is_not_safe(self):
        assert not _is_json_safe(float('inf'))
        assert not _is_json_safe(float('-inf'))

    def test_nan_is_not_safe(self):
        assert not _is_json_safe(float('nan'))

    def test_nested_structures(self):
        assert _is_json_safe([1, 2, 3])
        assert _is_json_safe({"a": 1})
        assert _is_json_safe({"nested": {"list": [1, 2]}})
```

### File: `test/snakebridge/python_ref_safety_integration_test.exs` (NEW)

```elixir
defmodule SnakeBridge.PythonRefSafetyIntegrationTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  describe "numpy arrays return refs" do
    @tag :requires_numpy
    test "numpy.array returns ref" do
      {:ok, ref} = SnakeBridge.call("numpy", "array", [[1, 2, 3]])
      assert %SnakeBridge.Ref{} = ref
    end

    @tag :requires_numpy
    test "numpy operations return refs" do
      {:ok, arr} = SnakeBridge.call("numpy", "array", [[1, 2, 3]])
      {:ok, result} = SnakeBridge.Dynamic.call(arr, :__add__, [arr])
      # Result is another array, should be ref
      assert %SnakeBridge.Ref{} = result
    end
  end

  describe "custom class instances return refs" do
    test "class instantiation returns ref" do
      # pathlib.Path is a good stdlib example
      {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
      assert %SnakeBridge.Ref{} = ref
    end

    test "method returning object returns ref" do
      {:ok, path} = SnakeBridge.call("pathlib", "Path", ["."])
      {:ok, parent} = SnakeBridge.Dynamic.call(path, :parent, [])
      # parent is also a Path, should be ref
      assert is_binary(parent) or %SnakeBridge.Ref{} = parent
    end
  end

  describe "generators return stream refs" do
    test "range returns stream ref for iteration" do
      {:ok, ref} = SnakeBridge.call("builtins", "iter", [
        SnakeBridge.call!("builtins", "range", [5])
      ])
      # Should be stream ref or regular ref
      assert %SnakeBridge.StreamRef{} = ref or %SnakeBridge.Ref{} = ref
    end
  end

  describe "primitive values pass through" do
    test "int returns int" do
      {:ok, result} = SnakeBridge.call("builtins", "int", ["42"])
      assert result == 42
    end

    test "str returns str" do
      {:ok, result} = SnakeBridge.call("builtins", "str", [42])
      assert result == "42"
    end

    test "list of primitives returns list" do
      {:ok, result} = SnakeBridge.call("builtins", "list", [[1, 2, 3]])
      assert result == [1, 2, 3]
    end
  end

  describe "nested non-serializable values" do
    test "list containing non-serializable returns ref" do
      # Create a list with a Path object
      {:ok, ref} = SnakeBridge.call("builtins", "eval", ["[1, __import__('pathlib').Path('.'), 3]"])
      # Entire result should be ref because it contains non-serializable
      assert %SnakeBridge.Ref{} = ref
    end
  end
end
```

## Edge Cases

1. **Empty collections**: `[]`, `{}` should pass through as JSON
2. **Nested depth**: Deeply nested structures with one non-serializable item
3. **Circular references**: Python objects with circular refs → ref-wrap
4. **Large objects**: Multi-GB numpy arrays → ref (never try to serialize)
5. **Exceptions as values**: `encode(ValueError("msg"))` → ref
6. **Built-in types**: `encode(type)` → ref

## Performance Considerations

- **Type checking overhead**: Minimal - isinstance() is fast
- **JSON safety validation**: Only runs after encode(), usually quick
- **Ref creation**: Small overhead, but correctness > speed here

## Backwards Compatibility

This is a **tightening** of guarantees:
- Code that received partial/lossy encodings before now receives refs
- Code that expected specific encoded shapes may need adjustment
- No silent data loss after this change

## Related Changes

- Requires [04-tagged-dict.md](./04-tagged-dict.md) for proper dict encoding
- Complements [05-encoder-fallback.md](./05-encoder-fallback.md) for Elixir-side fail-fast
- Used by [07-universal-api.md](./07-universal-api.md) for reliable API behavior
