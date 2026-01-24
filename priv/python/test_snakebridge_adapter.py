"""
Tests for SnakeBridge adapter encode_result graceful serialization.

These tests verify that containers with non-serializable items preserve
their structure, with only the non-serializable leaf objects becoming refs.
"""

import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from snakebridge_adapter import (
    encode_result,
    _instance_registry,
    _resolve_ref,
    _is_json_safe,
    _registry_key_prefix,
)
from snakebridge_types import Atom, SCHEMA_VERSION


class CustomObject:
    """A custom class that cannot be JSON serialized."""
    def __init__(self, value=42):
        self.value = value


class HashableCustom:
    """A hashable custom class for set testing."""
    def __init__(self, value=42):
        self.value = value

    def __hash__(self):
        return hash(self.value)

    def __eq__(self, other):
        return isinstance(other, HashableCustom) and self.value == other.value


class TestEncodeResultGraceful:
    """Test that encode_result preserves container structure with nested refs."""

    def test_list_with_custom_object_preserves_structure(self):
        """List with custom object should preserve list, ref-wrap only the object."""
        obj = CustomObject()
        result = encode_result([1, obj, 3], "test-session", "test", "test")

        # Result should be a list, not a ref
        assert isinstance(result, list), f"Expected list, got {type(result)}"
        assert len(result) == 3

        # First and third elements should be primitives
        assert result[0] == 1
        assert result[2] == 3

        # Second element should be a ref payload
        ref_payload = result[1]
        assert isinstance(ref_payload, dict)
        assert ref_payload.get("__type__") == "ref"
        assert "id" in ref_payload
        assert ref_payload.get("session_id") == "test-session"
        assert ref_payload.get("type_name") == "CustomObject"
        assert ref_payload.get("__type_name__") == "CustomObject"

    def test_dict_with_custom_object_preserves_structure(self):
        """Dict with custom object value should preserve dict, ref-wrap only the value."""
        obj = CustomObject()
        result = encode_result({"a": 1, "b": obj}, "test-session", "test", "test")

        # Result should be a dict, not a ref
        assert isinstance(result, dict), f"Expected dict, got {type(result)}"
        assert "__type__" not in result or result.get("__type__") != "ref"

        # Key "a" should have primitive value
        assert result["a"] == 1

        # Key "b" should have ref payload
        ref_payload = result["b"]
        assert isinstance(ref_payload, dict)
        assert ref_payload.get("__type__") == "ref"
        assert ref_payload.get("type_name") == "CustomObject"

    def test_nested_structure_history_like(self):
        """History-like structure should preserve list/dict with only response as ref."""
        response_obj = CustomObject()
        history = [
            {
                "model": "gpt-4",
                "response": response_obj,
                "cost": 1.23,
                "prompt_tokens": 100,
                "completion_tokens": 50,
            }
        ]

        result = encode_result(history, "test-session", "test", "test")

        # Result should be a list
        assert isinstance(result, list), f"Expected list, got {type(result)}"
        assert len(result) == 1

        # Entry should be a dict
        entry = result[0]
        assert isinstance(entry, dict), f"Expected dict, got {type(entry)}"

        # Serializable fields should be preserved
        assert entry["model"] == "gpt-4"
        assert entry["cost"] == 1.23
        assert entry["prompt_tokens"] == 100
        assert entry["completion_tokens"] == 50

        # Response should be a ref
        ref_payload = entry["response"]
        assert isinstance(ref_payload, dict)
        assert ref_payload.get("__type__") == "ref"
        assert ref_payload.get("type_name") == "CustomObject"

    def test_cycle_detection(self):
        """Cyclic structures should not cause infinite recursion."""
        lst = []
        lst.append(lst)  # Self-referential list

        result = encode_result(lst, "test-session", "test", "test")

        # Result should be a list containing a ref (not infinite recursion)
        assert isinstance(result, list), f"Expected list, got {type(result)}"
        assert len(result) == 1

        # The nested element should be a ref pointing to the same list
        ref_payload = result[0]
        assert isinstance(ref_payload, dict)
        assert ref_payload.get("__type__") == "ref"

    def test_iterator_nested_in_dict(self):
        """Iterator nested in dict should become stream_ref, dict preserved."""
        gen = (x for x in range(3))
        result = encode_result({"stream": gen, "ok": 1}, "test-session", "test", "test")

        # Result should be a dict, not a ref
        assert isinstance(result, dict)
        assert "__type__" not in result or result.get("__type__") != "ref"

        # "ok" should be preserved
        assert result["ok"] == 1

        # "stream" should be a stream_ref
        stream_ref = result["stream"]
        assert isinstance(stream_ref, dict)
        assert stream_ref.get("__type__") == "stream_ref"

    def test_ref_stored_in_registry(self):
        """Ref payloads should have objects stored in registry."""
        obj = CustomObject(value=999)
        result = encode_result([obj], "test-session", "test", "test")

        # Get the ref payload
        ref_payload = result[0]
        ref_id = ref_payload["id"]
        session_id = ref_payload["session_id"]

        # Verify registry contains the object
        key = f"{session_id}:{ref_id}"
        assert key in _instance_registry

        # Resolve and verify identity
        resolved = _resolve_ref(ref_payload, session_id)
        assert resolved is obj
        assert resolved.value == 999

    def test_deeply_nested_custom_object(self):
        """Deeply nested custom objects should become refs at correct depth."""
        obj = CustomObject()
        nested = {"level1": {"level2": {"level3": [1, 2, obj, 4]}}}

        result = encode_result(nested, "test-session", "test", "test")

        # Verify structure is preserved
        assert isinstance(result, dict)
        assert isinstance(result["level1"], dict)
        assert isinstance(result["level1"]["level2"], dict)
        assert isinstance(result["level1"]["level2"]["level3"], list)

        # Verify the custom object is a ref
        inner_list = result["level1"]["level2"]["level3"]
        assert inner_list[0] == 1
        assert inner_list[1] == 2
        assert inner_list[3] == 4
        assert inner_list[2].get("__type__") == "ref"

    def test_tuple_with_custom_object(self):
        """Tuple with custom object should preserve tuple structure."""
        obj = CustomObject()
        result = encode_result((1, obj, 3), "test-session", "test", "test")

        # Result should be a tagged tuple
        assert isinstance(result, dict)
        assert result.get("__type__") == "tuple"

        elements = result["elements"]
        assert len(elements) == 3
        assert elements[0] == 1
        assert elements[2] == 3

        # Middle element should be ref
        assert elements[1].get("__type__") == "ref"

    def test_set_with_custom_object(self):
        """Set with custom object should preserve set structure."""
        obj = HashableCustom()
        result = encode_result({1, 2, obj}, "test-session", "test", "test")

        # Result should be a tagged set
        assert isinstance(result, dict)
        assert result.get("__type__") == "set"

        elements = result["elements"]
        # Should have 3 elements
        assert len(elements) == 3

        # One element should be a ref
        refs = [e for e in elements if isinstance(e, dict) and e.get("__type__") == "ref"]
        assert len(refs) == 1

    def test_frozenset_with_custom_object(self):
        """Frozenset with custom object should preserve frozenset structure."""
        obj = HashableCustom()
        result = encode_result(frozenset([1, 2, obj]), "test-session", "test", "test")

        # Result should be a tagged frozenset
        assert isinstance(result, dict)
        assert result.get("__type__") == "frozenset"

        elements = result["elements"]
        refs = [e for e in elements if isinstance(e, dict) and e.get("__type__") == "ref"]
        assert len(refs) == 1

    def test_dict_with_non_string_keys(self):
        """Dict with non-string keys should use tagged dict format with nested refs."""
        obj = CustomObject()
        result = encode_result({1: "one", 2: obj}, "test-session", "test", "test")

        # Result should be a tagged dict
        assert isinstance(result, dict)
        assert result.get("__type__") == "dict"

        pairs = result["pairs"]
        assert len(pairs) == 2

        # Find the pair with value=obj (should be ref)
        for pair in pairs:
            key, val = pair[0], pair[1]
            if key == 2:
                assert isinstance(val, dict)
                assert val.get("__type__") == "ref"

    def test_multiple_custom_objects_in_list(self):
        """Multiple custom objects should each become separate refs."""
        obj1 = CustomObject(1)
        obj2 = CustomObject(2)
        result = encode_result([obj1, "middle", obj2], "test-session", "test", "test")

        assert isinstance(result, list)
        assert len(result) == 3
        assert result[1] == "middle"

        # Both objects should be refs with different IDs
        ref1 = result[0]
        ref2 = result[2]
        assert ref1.get("__type__") == "ref"
        assert ref2.get("__type__") == "ref"
        assert ref1["id"] != ref2["id"]

    def test_result_is_json_safe(self):
        """encode_result output should always be JSON-safe."""
        obj = CustomObject()
        cases = [
            [1, obj, 3],
            {"a": obj, "b": 2},
            {"nested": {"deep": [obj]}},
            (1, obj),
            {1, HashableCustom()},
        ]

        for case in cases:
            result = encode_result(case, "test-session", "test", "test")
            assert _is_json_safe(result), f"Result not JSON-safe for {case}"

    def test_empty_containers(self):
        """Empty containers should encode correctly."""
        assert encode_result([], "test", "test", "test") == []
        assert encode_result({}, "test", "test", "test") == {}

        tuple_result = encode_result((), "test", "test", "test")
        assert tuple_result.get("__type__") == "tuple"
        assert tuple_result["elements"] == []

    def test_primitives_pass_through(self):
        """Primitive values should pass through unchanged."""
        assert encode_result(None, "test", "test", "test") is None
        assert encode_result(True, "test", "test", "test") is True
        assert encode_result(False, "test", "test", "test") is False
        assert encode_result(42, "test", "test", "test") == 42
        assert encode_result(3.14, "test", "test", "test") == 3.14
        assert encode_result("hello", "test", "test", "test") == "hello"

    def test_bytes_encoding(self):
        """Bytes should be tagged correctly."""
        result = encode_result(b"hello", "test", "test", "test")
        assert result.get("__type__") == "bytes"
        assert result.get("data") == "aGVsbG8="

    def test_datetime_encoding(self):
        """Datetime should be tagged correctly."""
        from datetime import datetime
        dt = datetime(2024, 1, 15, 12, 30, 45)
        result = encode_result(dt, "test", "test", "test")
        assert result.get("__type__") == "datetime"
        assert "2024-01-15" in result.get("value", "")


class TestEncodeResultRefMetadata:
    """Test that ref payloads include required metadata."""

    def test_ref_has_type_name(self):
        """Ref payload should include type_name."""
        obj = CustomObject()
        result = encode_result([obj], "test-session", "test", "test")

        ref_payload = result[0]
        assert "type_name" in ref_payload
        assert ref_payload["type_name"] == "CustomObject"

    def test_ref_has_double_underscore_type_name(self):
        """Ref payload should include __type_name__ for SnakeBridge.Ref compatibility."""
        obj = CustomObject()
        result = encode_result([obj], "test-session", "test", "test")

        ref_payload = result[0]
        assert "__type_name__" in ref_payload
        assert ref_payload["__type_name__"] == "CustomObject"

    def test_ref_has_session_id(self):
        """Ref payload should include session_id."""
        obj = CustomObject()
        result = encode_result([obj], "my-session", "test", "test")

        ref_payload = result[0]
        assert ref_payload.get("session_id") == "my-session"

    def test_ref_has_python_module(self):
        """Ref payload should include python_module."""
        obj = CustomObject()
        result = encode_result([obj], "test", "mymodule", "mylib")

        ref_payload = result[0]
        assert ref_payload.get("python_module") == "mymodule"

    def test_ref_has_library(self):
        """Ref payload should include library."""
        obj = CustomObject()
        result = encode_result([obj], "test", "mymodule", "mylib")

        ref_payload = result[0]
        assert ref_payload.get("library") == "mylib"


class TestCycleDetection:
    """Test cycle detection in various structures."""

    def test_self_referential_list(self):
        """Self-referential list should not cause stack overflow."""
        lst = [1, 2]
        lst.append(lst)

        result = encode_result(lst, "test", "test", "test")
        assert isinstance(result, list)
        # The third element should be a ref to avoid infinite recursion
        assert result[2].get("__type__") == "ref"

    def test_mutually_referential_dicts(self):
        """Mutually referential dicts should not cause stack overflow."""
        a = {"name": "a"}
        b = {"name": "b"}
        a["other"] = b
        b["other"] = a

        result = encode_result(a, "test", "test", "test")
        assert isinstance(result, dict)
        assert result["name"] == "a"

        # b should be a dict with "other" being a ref back to a
        b_result = result["other"]
        assert isinstance(b_result, dict)
        assert b_result["name"] == "b"
        assert b_result["other"].get("__type__") == "ref"

    def test_deeply_nested_cycle(self):
        """Deeply nested cycles should be detected."""
        root = {"level": 0}
        current = root
        for i in range(1, 10):
            current["child"] = {"level": i}
            current = current["child"]
        # Create cycle back to root
        current["child"] = root

        result = encode_result(root, "test", "test", "test")

        # Navigate to the deepest level and verify cycle is broken with ref
        current_result = result
        for i in range(10):
            current_result = current_result["child"]

        assert current_result.get("__type__") == "ref"


class TestRecursionErrorFallback:
    """Test RecursionError fallback behavior for deeply nested structures."""

    def test_deeply_nested_list_returns_ref_on_recursion_error(self):
        """Deeply nested structure that would cause RecursionError returns ref."""
        # Create a deeply nested structure that exceeds Python's recursion limit
        # Python default recursion limit is ~1000, so 2000 levels should trigger it
        import sys
        current_limit = sys.getrecursionlimit()

        # Create nested structure deeper than recursion limit
        nested = [1]
        current = nested
        for _ in range(current_limit + 100):
            new_list = [1]
            current.append(new_list)
            current = new_list

        result = encode_result(nested, "test-session", "test", "test")

        # Instead of raising RecursionError, should return a ref
        assert isinstance(result, dict), f"Expected dict (ref), got {type(result)}"
        assert result.get("__type__") == "ref"
        assert "id" in result
        assert result.get("session_id") == "test-session"

    def test_moderate_nesting_encodes_normally(self):
        """Moderately nested structures should encode normally without fallback."""
        # 50 levels of nesting should work fine
        nested = {"value": 1}
        current = nested
        for i in range(50):
            current["child"] = {"value": i + 2}
            current = current["child"]

        result = encode_result(nested, "test-session", "test", "test")

        # Should be a regular dict, not a ref fallback
        assert isinstance(result, dict)
        assert result.get("__type__") != "ref"
        assert result["value"] == 1
        assert "child" in result

    def test_fallback_cleans_up_partial_refs(self):
        """On fallback, refs created during partial encoding are cleaned up."""
        import sys

        test_session = "cleanup-test-session"

        # Count refs for our specific session before
        def count_session_refs():
            prefix = _registry_key_prefix(test_session)
            return sum(1 for k in _instance_registry.keys() if k.startswith(prefix))

        initial_count = count_session_refs()

        # Create a structure with a custom object that will create a ref,
        # followed by deep nesting that will trigger RecursionError
        obj = CustomObject(value=42)
        current_limit = sys.getrecursionlimit()

        # Structure: [custom_object, deeply_nested_list]
        # The custom_object will create a ref, then deep nesting will fail
        deeply_nested = [1]
        current = deeply_nested
        for _ in range(current_limit + 100):
            new_list = [1]
            current.append(new_list)
            current = new_list

        test_structure = [obj, deeply_nested]

        # This should fall back to wrapping the whole structure
        result = encode_result(test_structure, test_session, "test", "test")

        # Should have fallen back to a single ref for the whole structure
        assert result.get("__type__") == "ref"

        # Count refs for our session after - should be exactly 1 (the fallback ref)
        # The partial ref from obj should have been cleaned up
        final_count = count_session_refs()
        refs_created = final_count - initial_count

        # Should only have 1 new ref (the fallback), not 2 (obj ref was cleaned)
        assert refs_created == 1, f"Expected 1 ref (fallback only), got {refs_created}"


class TestAsyncGeneratorHandling:
    """Test that async generators become refs, not stream_refs."""

    def test_async_generator_becomes_ref(self):
        """Async generator should become ref, not stream_ref (cannot be consumed via next)."""
        import sys
        import asyncio
        if sys.version_info < (3, 6):
            # Async generators not available before Python 3.6
            return

        # Create an async generator
        async def async_gen():
            for i in range(3):
                yield i

        gen = async_gen()

        result = encode_result(gen, "test-session", "test", "test")

        # Should be a ref, NOT a stream_ref
        assert isinstance(result, dict)
        assert result.get("__type__") == "ref", f"Expected ref, got {result.get('__type__')}"
        assert "id" in result
        assert result.get("session_id") == "test-session"
        assert result.get("type_name") == "async_generator"

        # Cleanup - aclose() returns a coroutine that must be awaited
        asyncio.run(gen.aclose())

    def test_sync_generator_still_becomes_stream_ref(self):
        """Sync generators should still become stream_refs."""
        gen = (x for x in range(3))

        result = encode_result(gen, "test-session", "test", "test")

        # Should be a stream_ref
        assert isinstance(result, dict)
        assert result.get("__type__") == "stream_ref"

    def test_async_generator_nested_in_dict_becomes_ref(self):
        """Async generator nested in dict should become ref, dict preserved."""
        import sys
        import asyncio
        if sys.version_info < (3, 6):
            return

        async def async_gen():
            for i in range(3):
                yield i

        gen = async_gen()

        result = encode_result({"stream": gen, "ok": 1}, "test-session", "test", "test")

        # Dict should be preserved
        assert isinstance(result, dict)
        assert result.get("__type__") != "ref"  # Dict itself is not a ref
        assert result["ok"] == 1

        # Async generator should be a ref (not stream_ref)
        stream_result = result["stream"]
        assert isinstance(stream_result, dict)
        assert stream_result.get("__type__") == "ref"

        # Cleanup - aclose() returns a coroutine that must be awaited
        asyncio.run(gen.aclose())


class TestRefMemoization:
    """Test that repeated objects yield the same ref payload (deduplication)."""

    def test_same_object_yields_same_ref_id(self):
        """Same object appearing multiple times should yield same ref id."""
        obj = CustomObject(value=42)
        result = encode_result([obj, "separator", obj], "test-session", "test", "test")

        assert isinstance(result, list)
        assert len(result) == 3
        assert result[1] == "separator"

        # Both refs should have the same id since it's the same object
        ref1 = result[0]
        ref2 = result[2]
        assert ref1.get("__type__") == "ref"
        assert ref2.get("__type__") == "ref"
        assert ref1["id"] == ref2["id"], "Same object should yield same ref id"

    def test_different_objects_yield_different_ref_ids(self):
        """Different objects should yield different ref ids."""
        obj1 = CustomObject(value=1)
        obj2 = CustomObject(value=2)
        result = encode_result([obj1, obj2], "test-session", "test", "test")

        ref1 = result[0]
        ref2 = result[1]
        assert ref1["id"] != ref2["id"], "Different objects should have different ref ids"

    def test_same_object_in_nested_structure_yields_same_ref(self):
        """Same object appearing at different nesting levels should yield same ref."""
        obj = CustomObject(value=99)
        nested = {
            "shallow": obj,
            "deep": {
                "deeper": {
                    "deepest": obj
                }
            }
        }

        result = encode_result(nested, "test-session", "test", "test")

        shallow_ref = result["shallow"]
        deepest_ref = result["deep"]["deeper"]["deepest"]

        assert shallow_ref.get("__type__") == "ref"
        assert deepest_ref.get("__type__") == "ref"
        assert shallow_ref["id"] == deepest_ref["id"]

    def test_generator_memoization(self):
        """Same generator appearing multiple times should yield same stream_ref id."""
        gen = (x for x in range(3))
        # Put the same generator object in multiple places in a dict
        # This tests that ref_memo deduplicates stream_refs
        result = encode_result({"a": gen, "b": gen}, "test-session", "test", "test")

        # Both should be stream_refs
        assert result["a"].get("__type__") == "stream_ref"
        assert result["b"].get("__type__") == "stream_ref"

        # Both should have the same id (memoization)
        assert result["a"]["id"] == result["b"]["id"], \
            "Same generator should yield same stream_ref id"

    def test_cycle_uses_memoization(self):
        """Cyclic structures should use memoized refs for back-references."""
        lst = [1, 2]
        lst.append(lst)  # Self-reference

        result = encode_result(lst, "test-session", "test", "test")

        # The cyclic reference should be a memoized ref
        cyclic_ref = result[2]
        assert cyclic_ref.get("__type__") == "ref"


class TestAtomEncoding:
    """Test that Atom objects encode as tagged atoms, not refs."""

    def test_atom_encodes_as_tagged_atom(self):
        """Atom should encode as a tagged atom value, not a ref."""
        atom = Atom("ok")
        result = encode_result(atom, "test-session", "test", "test")

        # Result should be a tagged atom, not a ref
        assert isinstance(result, dict)
        assert result.get("__type__") == "atom"
        assert result.get("value") == "ok"
        assert result.get("__schema__") == SCHEMA_VERSION

    def test_atom_in_list_encodes_correctly(self):
        """Atom nested in a list should encode as tagged atom."""
        atom = Atom("error")
        result = encode_result([1, atom, 3], "test-session", "test", "test")

        assert isinstance(result, list)
        assert len(result) == 3
        assert result[0] == 1
        assert result[2] == 3

        # Middle element should be tagged atom
        atom_result = result[1]
        assert isinstance(atom_result, dict)
        assert atom_result.get("__type__") == "atom"
        assert atom_result.get("value") == "error"

    def test_atom_in_dict_encodes_correctly(self):
        """Atom nested in a dict should encode as tagged atom."""
        atom = Atom("nil")
        result = encode_result({"status": atom, "count": 42}, "test", "test", "test")

        assert isinstance(result, dict)
        assert result["count"] == 42

        status_result = result["status"]
        assert isinstance(status_result, dict)
        assert status_result.get("__type__") == "atom"
        assert status_result.get("value") == "nil"

    def test_atom_is_json_safe(self):
        """Encoded atoms should be JSON-safe."""
        atom = Atom("test")
        result = encode_result(atom, "test", "test", "test")
        assert _is_json_safe(result)


# Simple test runner for when pytest is not available
def run_tests():
    """Run all tests and report results."""
    import traceback

    test_classes = [
        TestEncodeResultGraceful,
        TestEncodeResultRefMetadata,
        TestCycleDetection,
        TestRecursionErrorFallback,
        TestAsyncGeneratorHandling,
        TestRefMemoization,
        TestAtomEncoding,
    ]

    total = 0
    passed = 0
    failed = 0

    for test_class in test_classes:
        print(f"\n{test_class.__name__}:")
        instance = test_class()
        for name in dir(instance):
            if name.startswith('test_'):
                total += 1
                try:
                    getattr(instance, name)()
                    passed += 1
                    print(f"  PASS: {name}")
                except AssertionError as e:
                    failed += 1
                    print(f"  FAIL: {name}")
                    print(f"        {e}")
                except Exception as e:
                    failed += 1
                    print(f"  ERROR: {name}")
                    traceback.print_exc()

    print(f"\n{'=' * 60}")
    print(f"Results: {passed}/{total} passed, {failed} failed")
    return failed == 0


if __name__ == "__main__":
    # Try pytest first, fall back to simple runner
    try:
        import pytest
        sys.exit(pytest.main([__file__, "-v"]))
    except ImportError:
        print("pytest not available, using simple test runner\n")
        success = run_tests()
        sys.exit(0 if success else 1)
