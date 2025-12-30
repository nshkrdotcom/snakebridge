"""
Tests for SnakeBridge type encoding ref safety.

These tests verify that non-JSON-serializable values are properly marked
with __needs_ref__ or __needs_stream_ref__ markers.
"""

import math
import sys
import os
import tempfile

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from snakebridge_types import encode, _is_generator_or_iterator, _get_stream_type
from snakebridge_adapter import _is_json_safe


class TestEncodeRefSafety:
    """Test that non-JSON-safe values result in __needs_ref__."""

    def test_custom_class_needs_ref(self):
        """Custom class instances should need refs."""
        class MyClass:
            pass

        result = encode(MyClass())
        assert result.get("__needs_ref__") is True
        assert result.get("__type_name__") == "MyClass"

    def test_lambda_needs_ref(self):
        """Lambda functions should need refs."""
        fn = lambda x: x + 1
        result = encode(fn)
        assert result.get("__needs_ref__") is True
        assert result.get("__type_name__") == "function"

    def test_generator_needs_stream_ref(self):
        """Generators should need stream refs."""
        gen = (x for x in range(10))
        result = encode(gen)
        assert result.get("__needs_stream_ref__") is True
        assert result.get("__stream_type__") == "generator"

    def test_iterator_needs_stream_ref(self):
        """Iterators should need stream refs."""
        it = iter([1, 2, 3])
        result = encode(it)
        assert result.get("__needs_stream_ref__") is True
        assert result.get("__stream_type__") == "iterator"

    def test_file_handle_needs_ref(self):
        """File handles should need refs (context managers)."""
        with tempfile.NamedTemporaryFile(delete=False) as f:
            temp_path = f.name

        try:
            with open(temp_path, 'r') as handle:
                result = encode(handle)
                # File handles are context managers, so they get regular refs not stream refs
                assert result.get("__needs_ref__") is True
        finally:
            os.unlink(temp_path)

    def test_list_with_unencodable_needs_ref(self):
        """List containing non-serializable item should need ref."""
        class MyClass:
            pass

        lst = [1, 2, MyClass(), 4]
        result = encode(lst)
        assert result.get("__needs_ref__") is True
        assert "contains unencodable item" in result.get("__reason__", "")
        assert result.get("__type_name__") == "list"

    def test_dict_with_unencodable_value_needs_ref(self):
        """Dict with non-serializable value should need ref."""
        class MyClass:
            pass

        d = {"key": MyClass()}
        result = encode(d)
        assert result.get("__needs_ref__") is True
        assert "unencodable value" in result.get("__reason__", "")
        assert result.get("__type_name__") == "dict"

    def test_tuple_with_unencodable_needs_ref(self):
        """Tuple containing non-serializable item should need ref."""
        class MyClass:
            pass

        t = (1, MyClass(), 3)
        result = encode(t)
        assert result.get("__needs_ref__") is True
        assert result.get("__type_name__") == "tuple"

    def test_set_with_unencodable_needs_ref(self):
        """Set containing non-serializable item should need ref."""
        class MyClass:
            def __hash__(self):
                return 42

        s = {1, MyClass(), 3}
        result = encode(s)
        assert result.get("__needs_ref__") is True
        assert result.get("__type_name__") == "set"

    def test_nested_unencodable_needs_ref(self):
        """Deeply nested non-serializable should bubble up __needs_ref__."""
        class MyClass:
            pass

        nested = {"outer": {"inner": [1, 2, MyClass()]}}
        result = encode(nested)
        assert result.get("__needs_ref__") is True

    def test_list_with_generator_needs_ref(self):
        """List containing generator should need ref."""
        gen = (x for x in range(3))
        lst = [1, gen, 3]
        result = encode(lst)
        assert result.get("__needs_ref__") is True
        assert "iterator/generator" in result.get("__reason__", "")


class TestEncodeSafeValues:
    """Test that JSON-safe values encode correctly."""

    def test_none(self):
        """None should pass through."""
        assert encode(None) is None

    def test_booleans(self):
        """Booleans should pass through."""
        assert encode(True) is True
        assert encode(False) is False

    def test_integers(self):
        """Integers should pass through."""
        assert encode(42) == 42
        assert encode(-1) == -1
        assert encode(0) == 0

    def test_floats(self):
        """Regular floats should pass through."""
        assert encode(3.14) == 3.14
        assert encode(-0.5) == -0.5

    def test_strings(self):
        """Strings should pass through."""
        assert encode("hello") == "hello"
        assert encode("") == ""

    def test_list_of_primitives(self):
        """List of primitives should encode to list."""
        result = encode([1, 2, 3])
        assert result == [1, 2, 3]

    def test_dict_string_keys(self):
        """Dict with string keys should encode to plain dict."""
        result = encode({"a": 1, "b": 2})
        assert result == {"a": 1, "b": 2}

    def test_nested_safe_structures(self):
        """Nested safe structures should encode correctly."""
        result = encode({"list": [1, 2], "nested": {"key": "value"}})
        assert result == {"list": [1, 2], "nested": {"key": "value"}}

    def test_empty_list(self):
        """Empty list should pass through."""
        assert encode([]) == []

    def test_empty_dict(self):
        """Empty dict should pass through."""
        assert encode({}) == {}


class TestSpecialFloats:
    """Test special float handling."""

    def test_infinity_tagged(self):
        """Positive infinity should be tagged."""
        result = encode(float('inf'))
        assert result.get("__type__") == "special_float"
        assert result.get("value") == "infinity"

    def test_neg_infinity_tagged(self):
        """Negative infinity should be tagged."""
        result = encode(float('-inf'))
        assert result.get("__type__") == "special_float"
        assert result.get("value") == "neg_infinity"

    def test_nan_tagged(self):
        """NaN should be tagged."""
        result = encode(float('nan'))
        assert result.get("__type__") == "special_float"
        assert result.get("value") == "nan"


class TestTaggedTypes:
    """Test tagged type encoding."""

    def test_bytes(self):
        """Bytes should be tagged with base64."""
        result = encode(b'hello')
        assert result.get("__type__") == "bytes"
        assert result.get("data") == "aGVsbG8="  # base64 of 'hello'

    def test_tuple(self):
        """Tuple should be tagged."""
        result = encode((1, 2, 3))
        assert result.get("__type__") == "tuple"
        assert result.get("elements") == [1, 2, 3]

    def test_set(self):
        """Set should be tagged."""
        result = encode({1, 2, 3})
        assert result.get("__type__") == "set"
        assert sorted(result.get("elements")) == [1, 2, 3]

    def test_frozenset(self):
        """Frozenset should be tagged."""
        result = encode(frozenset([1, 2, 3]))
        assert result.get("__type__") == "frozenset"
        assert sorted(result.get("elements")) == [1, 2, 3]

    def test_complex(self):
        """Complex should be tagged."""
        result = encode(1 + 2j)
        assert result.get("__type__") == "complex"
        assert result.get("real") == 1.0
        assert result.get("imag") == 2.0


class TestTaggedDict:
    """Test tagged dict encoding for non-string keys."""

    def test_int_keys(self):
        """Dict with int keys should use tagged format."""
        result = encode({1: "one", 2: "two"})
        assert result.get("__type__") == "dict"
        assert "pairs" in result
        # Verify pairs structure
        pairs = result.get("pairs")
        assert len(pairs) == 2

    def test_tuple_keys(self):
        """Dict with tuple keys should use tagged format."""
        result = encode({(0, 0): "origin"})
        assert result.get("__type__") == "dict"
        pairs = result.get("pairs")
        assert len(pairs) == 1
        # Key should be encoded tuple
        assert pairs[0][0].get("__type__") == "tuple"

    def test_mixed_keys(self):
        """Dict with mixed key types should use tagged format."""
        result = encode({"string": 1, 2: "int_key"})
        assert result.get("__type__") == "dict"


class TestIsJsonSafe:
    """Test the JSON safety checker."""

    def test_primitives_safe(self):
        """Primitives should be JSON safe."""
        assert _is_json_safe(None)
        assert _is_json_safe(True)
        assert _is_json_safe(False)
        assert _is_json_safe(42)
        assert _is_json_safe(3.14)
        assert _is_json_safe("hello")

    def test_inf_not_safe(self):
        """Infinity should not be JSON safe."""
        assert not _is_json_safe(float('inf'))
        assert not _is_json_safe(float('-inf'))

    def test_nan_not_safe(self):
        """NaN should not be JSON safe."""
        assert not _is_json_safe(float('nan'))

    def test_list_safe(self):
        """Lists of safe values should be safe."""
        assert _is_json_safe([1, 2, 3])
        assert _is_json_safe([])

    def test_dict_safe(self):
        """Dicts with string keys and safe values should be safe."""
        assert _is_json_safe({"a": 1})
        assert _is_json_safe({})

    def test_nested_safe(self):
        """Nested structures should be safe if all values are safe."""
        assert _is_json_safe({"nested": {"list": [1, 2]}})

    def test_tagged_values_safe(self):
        """Tagged values should be safe."""
        assert _is_json_safe({"__type__": "bytes", "__schema__": 1, "data": "aGVsbG8="})
        assert _is_json_safe({"__type__": "tuple", "__schema__": 1, "elements": [1, 2]})
        assert _is_json_safe({"__type__": "ref", "id": "abc123", "session_id": "test"})


class TestGeneratorIteratorDetection:
    """Test generator/iterator detection helpers."""

    def test_generator_detected(self):
        """Generator should be detected."""
        gen = (x for x in range(3))
        assert _is_generator_or_iterator(gen)
        assert _get_stream_type(gen) == "generator"

    def test_iterator_detected(self):
        """Iterator should be detected."""
        it = iter([1, 2, 3])
        assert _is_generator_or_iterator(it)
        assert _get_stream_type(it) == "iterator"

    def test_string_not_iterator(self):
        """String should not be detected as iterator."""
        assert not _is_generator_or_iterator("hello")

    def test_list_not_iterator(self):
        """List should not be detected as iterator."""
        assert not _is_generator_or_iterator([1, 2, 3])


# Simple test runner for when pytest is not available
def run_tests():
    """Run all tests and report results."""
    import traceback

    test_classes = [
        TestEncodeRefSafety,
        TestEncodeSafeValues,
        TestSpecialFloats,
        TestTaggedTypes,
        TestTaggedDict,
        TestIsJsonSafe,
        TestGeneratorIteratorDetection,
    ]

    total = 0
    passed = 0
    failed = 0

    for test_class in test_classes:
        instance = test_class()
        for name in dir(instance):
            if name.startswith('test_'):
                total += 1
                try:
                    getattr(instance, name)()
                    passed += 1
                    print(f"  PASS: {test_class.__name__}.{name}")
                except AssertionError as e:
                    failed += 1
                    print(f"  FAIL: {test_class.__name__}.{name}")
                    print(f"        {e}")
                except Exception as e:
                    failed += 1
                    print(f"  ERROR: {test_class.__name__}.{name}")
                    traceback.print_exc()

    print(f"\n{'=' * 60}")
    print(f"Results: {passed}/{total} passed, {failed} failed")
    return failed == 0


if __name__ == "__main__":
    import sys

    # Try pytest first, fall back to simple runner
    try:
        import pytest
        sys.exit(pytest.main([__file__, "-v"]))
    except ImportError:
        print("pytest not available, using simple test runner\n")
        success = run_tests()
        sys.exit(0 if success else 1)
