"""
Tests for SnakeBridge Python Adapter.

Run with: pytest test_snakebridge_adapter.py
"""

import sys
import os
import unittest
from unittest.mock import Mock, patch

# Add parent directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from snakebridge_adapter import SnakeBridgeAdapter


class TestDescribeLibrary(unittest.TestCase):
    """Test the describe_library tool."""

    def setUp(self):
        self.adapter = SnakeBridgeAdapter()

    def test_describe_builtin_json_module(self):
        """Should introspect Python's built-in json module."""
        result = self.adapter.describe_library("json", discovery_depth=1)

        self.assertTrue(result["success"])
        self.assertIn("library_version", result)
        self.assertIn("functions", result)
        self.assertIn("classes", result)

        # json module has dumps and loads functions
        self.assertIn("dumps", result["functions"])
        self.assertIn("loads", result["functions"])

        # Each function should have metadata
        dumps_func = result["functions"]["dumps"]
        self.assertEqual(dumps_func["name"], "dumps")
        self.assertIn("python_path", dumps_func)
        self.assertIn("docstring", dumps_func)

    def test_describe_nonexistent_module_returns_error(self):
        """Should handle missing modules gracefully."""
        result = self.adapter.describe_library("nonexistent_module_xyz")

        self.assertFalse(result["success"])
        self.assertIn("error", result)
        self.assertIn("No module named", result["error"])

    def test_describe_library_includes_classes(self):
        """Should discover classes in modules."""
        # Use a module we know has classes
        result = self.adapter.describe_library("unittest", discovery_depth=1)

        self.assertTrue(result["success"])
        self.assertIn("TestCase", result["classes"])

        test_case_class = result["classes"]["TestCase"]
        self.assertEqual(test_case_class["name"], "TestCase")
        self.assertIn("methods", test_case_class)

    def test_discovery_depth_limits_recursion(self):
        """Should respect discovery_depth parameter."""
        # Shallow discovery
        shallow = self.adapter.describe_library("os", discovery_depth=1)

        # Deep discovery
        deep = self.adapter.describe_library("os", discovery_depth=3)

        self.assertTrue(shallow["success"])
        self.assertTrue(deep["success"])

        # Deep should have more details (for now, just verify it works)
        # Full depth validation can be added later


class TestCallPython(unittest.TestCase):
    """Test the call_python tool."""

    def setUp(self):
        self.adapter = SnakeBridgeAdapter()

    def test_call_module_function(self):
        """Should call module-level functions."""
        # Call json.dumps({"test": "data"})
        result = self.adapter.call_python(
            module_path="json",
            function_name="dumps",
            args=[],
            kwargs={"obj": {"test": "data"}}
        )

        self.assertTrue(result["success"])
        self.assertIn("result", result)

        # Result should be JSON string
        json_string = result["result"]
        self.assertIn("test", json_string)
        self.assertIn("data", json_string)

    def test_call_function_with_args(self):
        """Should handle positional arguments."""
        # Call json.loads('{"hello": "world"}')
        result = self.adapter.call_python(
            module_path="json",
            function_name="loads",
            args=['{"hello": "world"}'],
            kwargs={}
        )

        self.assertTrue(result["success"])
        self.assertEqual(result["result"], {"hello": "world"})

    def test_create_instance_stores_and_returns_id(self):
        """Should create instances when function_name is __init__."""
        # Create instance: unittest.TestCase()
        result = self.adapter.call_python(
            module_path="unittest.TestCase",
            function_name="__init__",
            args=[],
            kwargs={}
        )

        self.assertTrue(result["success"])
        self.assertIn("instance_id", result)

        # Instance should be stored
        instance_id = result["instance_id"]
        self.assertIn(instance_id, self.adapter.instances)

    def test_call_instance_method(self):
        """Should call methods on stored instances."""
        # Create instance first
        create_result = self.adapter.call_python(
            module_path="unittest.TestCase",
            function_name="__init__",
            args=[],
            kwargs={}
        )

        instance_id = create_result["instance_id"]

        # Call method on instance
        # Use instance:<id> format
        result = self.adapter.call_python(
            module_path=f"instance:{instance_id}",
            function_name="assertEqual",
            args=[1, 1],
            kwargs={}
        )

        # assertEqual returns None, but should not raise
        self.assertTrue(result["success"])

    def test_call_nonexistent_function_returns_error(self):
        """Should handle errors gracefully."""
        result = self.adapter.call_python(
            module_path="json",
            function_name="nonexistent_function",
            args=[],
            kwargs={}
        )

        self.assertFalse(result["success"])
        self.assertIn("error", result)

    def test_call_with_invalid_arguments_returns_error(self):
        """Should catch and return errors from Python exceptions."""
        # json.dumps requires an argument
        result = self.adapter.call_python(
            module_path="json",
            function_name="dumps",
            args=[],
            kwargs={}  # Missing required 'obj' argument
        )

        self.assertFalse(result["success"])
        self.assertIn("error", result)


class TestInstanceManagement(unittest.TestCase):
    """Test instance lifecycle."""

    def setUp(self):
        self.adapter = SnakeBridgeAdapter()

    def test_multiple_instances_are_isolated(self):
        """Should store multiple instances separately."""
        # Create two instances
        result1 = self.adapter.call_python("unittest.TestCase", "__init__", [], {})
        result2 = self.adapter.call_python("unittest.TestCase", "__init__", [], {})

        id1 = result1["instance_id"]
        id2 = result2["instance_id"]

        # Should have different IDs
        self.assertNotEqual(id1, id2)

        # Both should be stored
        self.assertIn(id1, self.adapter.instances)
        self.assertIn(id2, self.adapter.instances)

    def test_instance_cleanup(self):
        """Should be able to remove instances."""
        # This can be added later - for now just test storage works
        pass


if __name__ == "__main__":
    unittest.main()
