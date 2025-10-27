"""
SnakeBridge Python Adapter for Snakepit.

Provides dynamic Python library integration through introspection and
dynamic execution capabilities.
"""

import importlib
import inspect
import uuid
import logging
from typing import Any, Dict, List, Optional

# Import Snakepit base adapter
try:
    from snakepit_bridge.base_adapter_threaded import ThreadSafeAdapter, tool
    HAS_SNAKEPIT = True
except ImportError:
    # Fallback for standalone testing
    ThreadSafeAdapter = object
    HAS_SNAKEPIT = False

    def tool(description="", **kwargs):
        """Fallback tool decorator for testing"""
        def decorator(func):
            return func
        return decorator

logger = logging.getLogger(__name__)


class SnakeBridgeAdapter(ThreadSafeAdapter):
    """
    Snakepit adapter for dynamic Python library integration.

    Provides tools:
    - describe_library: Introspect Python modules
    - call_python: Execute Python code dynamically

    Note: This is a simplified version that doesn't inherit from ThreadSafeAdapter
    for easier standalone testing. The production version will inherit from
    snakepit_bridge.base_adapter_threaded.ThreadSafeAdapter.
    """

    def __init__(self):
        """Initialize adapter with instance storage."""
        if HAS_SNAKEPIT:
            super().__init__()
        self.instances = {}  # {instance_id: python_object}
        self.session_context = None
        self.initialized = False
        logger.info("SnakeBridgeAdapter initialized")

    def set_session_context(self, session_context):
        """Set the session context for this adapter instance."""
        self.session_context = session_context
        if hasattr(session_context, 'session_id'):
            logger.info(f"Session context set: {session_context.session_id}")

    async def initialize(self):
        """Initialize the adapter."""
        self.initialized = True
        logger.info("Adapter initialized")

    async def cleanup(self):
        """Clean up adapter resources."""
        self.initialized = False
        self.instances = {}
        logger.info("Adapter cleaned up")

    def execute_tool(self, tool_name: str, arguments: dict, context) -> dict:
        """
        Dispatch tool execution to appropriate @tool methods.

        This is the entry point called by Snakepit's gRPC server.
        """
        if tool_name == "describe_library":
            return self.describe_library(
                module_path=arguments.get("module_path"),
                discovery_depth=arguments.get("discovery_depth", 2)
            )
        elif tool_name == "call_python":
            return self.call_python(
                module_path=arguments.get("module_path"),
                function_name=arguments.get("function_name"),
                args=arguments.get("args"),
                kwargs=arguments.get("kwargs")
            )
        else:
            return {
                "success": False,
                "error": f"Unknown tool: {tool_name}"
            }

    @tool(description="Introspect Python module structure")
    def describe_library(self, module_path: str, discovery_depth: int = 2) -> dict:
        """
        Introspect a Python module and return its schema.

        Args:
            module_path: Python module path (e.g., "json", "dspy.Predict")
            discovery_depth: How deep to recurse into submodules (default: 2)

        Returns:
            dict: Schema with library_version, classes, functions
                {
                    "success": true/false,
                    "library_version": "x.y.z",
                    "classes": {...},
                    "functions": {...},
                    "error": "..." (if failed)
                }
        """
        try:
            # Import the module
            module = importlib.import_module(module_path)

            # Extract version
            version = getattr(module, "__version__", "unknown")

            # Introspect functions
            functions = self._introspect_functions(module, module_path)

            # Introspect classes
            classes = self._introspect_classes(module, module_path, discovery_depth)

            return {
                "success": True,
                "library_version": version,
                "functions": functions,
                "classes": classes
            }

        except ModuleNotFoundError as e:
            return {
                "success": False,
                "error": str(e)
            }
        except Exception as e:
            logger.error(f"Error introspecting {module_path}: {e}")
            return {
                "success": False,
                "error": str(e)
            }

    @tool(description="Execute Python code dynamically")
    def call_python(
        self,
        module_path: str,
        function_name: str,
        args: Optional[List] = None,
        kwargs: Optional[Dict] = None
    ) -> dict:
        """
        Dynamically execute Python code.

        Supports:
        - Module functions: call_python("json", "dumps", [], {"obj": {...}})
        - Instance creation: call_python("dspy.Predict", "__init__", [], {"signature": "q->a"})
        - Instance methods: call_python("instance:<id>", "forward", [], {...})

        Args:
            module_path: Module path or "instance:<id>" for stored instances
            function_name: Function/method name to call
            args: Positional arguments (default: [])
            kwargs: Keyword arguments (default: {})

        Returns:
            dict: Result or error
                {
                    "success": true/false,
                    "result": <value>,  (or "instance_id": <id> for __init__)
                    "error": "..." (if failed)
                }
        """
        args = args or []
        kwargs = kwargs or {}

        try:
            # Handle instance creation
            if function_name == "__init__":
                return self._create_instance(module_path, args, kwargs)

            # Handle instance method calls
            if module_path.startswith("instance:"):
                return self._call_instance_method(module_path, function_name, args, kwargs)

            # Handle module-level function calls
            return self._call_module_function(module_path, function_name, args, kwargs)

        except Exception as e:
            logger.error(f"Error calling {module_path}.{function_name}: {e}")
            return {
                "success": False,
                "error": str(e)
            }

    # Private helper methods

    def _introspect_functions(self, module, module_path: str) -> dict:
        """Introspect module-level functions."""
        functions = {}

        for name, obj in inspect.getmembers(module, inspect.isfunction):
            # Skip private functions
            if name.startswith("_"):
                continue

            functions[name] = {
                "name": name,
                "python_path": f"{module_path}.{name}",
                "docstring": inspect.getdoc(obj) or "",
                "parameters": self._get_function_parameters(obj)
            }

        return functions

    def _introspect_classes(self, module, module_path: str, depth: int) -> dict:
        """Introspect classes in module."""
        classes = {}

        for name, obj in inspect.getmembers(module, inspect.isclass):
            # Skip private classes and imports from other modules
            if name.startswith("_"):
                continue

            # Only include classes defined in this module
            if hasattr(obj, "__module__") and not obj.__module__.startswith(module_path):
                continue

            classes[name] = {
                "name": name,
                "python_path": f"{module_path}.{name}",
                "docstring": inspect.getdoc(obj) or "",
                "methods": self._get_class_methods(obj) if depth > 0 else []
            }

        return classes

    def _get_function_parameters(self, func) -> list:
        """Extract function parameters using inspect."""
        try:
            sig = inspect.signature(func)
            params = []

            for param_name, param in sig.parameters.items():
                params.append({
                    "name": param_name,
                    "required": param.default == inspect.Parameter.empty,
                    "default": None if param.default == inspect.Parameter.empty else str(param.default)
                })

            return params
        except (ValueError, TypeError):
            return []

    def _get_class_methods(self, cls) -> list:
        """Extract methods from a class."""
        methods = []

        for name, obj in inspect.getmembers(cls, inspect.ismethod):
            if name.startswith("_") and name != "__init__":
                continue

            methods.append({
                "name": name,
                "docstring": inspect.getdoc(obj) or "",
                "parameters": self._get_function_parameters(obj)
            })

        return methods

    def _create_instance(self, module_path: str, args: list, kwargs: dict) -> dict:
        """
        Create a Python instance and store it.

        Args:
            module_path: Full path to class (e.g., "dspy.Predict")
            args: Positional arguments for __init__
            kwargs: Keyword arguments for __init__

        Returns:
            dict: {"success": true, "instance_id": "<uuid>"}
        """
        # Parse module and class name
        parts = module_path.rsplit(".", 1)
        if len(parts) == 2:
            module_name, class_name = parts
            module = importlib.import_module(module_name)
            cls = getattr(module, class_name)
        else:
            # Assume it's a module-level callable
            module = importlib.import_module(module_path)
            cls = module

        # Create instance
        instance = cls(*args, **kwargs)

        # Store with unique ID
        instance_id = f"instance_{uuid.uuid4().hex[:12]}"
        self.instances[instance_id] = instance

        logger.info(f"Created instance {instance_id} of {module_path}")

        return {
            "success": True,
            "instance_id": instance_id
        }

    def _call_instance_method(
        self,
        instance_ref: str,
        method_name: str,
        args: list,
        kwargs: dict
    ) -> dict:
        """
        Call a method on a stored instance.

        Args:
            instance_ref: "instance:<id>" format
            method_name: Method to call
            args: Positional arguments
            kwargs: Keyword arguments

        Returns:
            dict: {"success": true, "result": <value>}
        """
        # Extract instance ID
        instance_id = instance_ref.replace("instance:", "")

        if instance_id not in self.instances:
            return {
                "success": False,
                "error": f"Instance {instance_id} not found"
            }

        # Get instance
        instance = self.instances[instance_id]

        # Call method
        method = getattr(instance, method_name)
        result = method(*args, **kwargs)

        return {
            "success": True,
            "result": result
        }

    def _call_module_function(
        self,
        module_path: str,
        function_name: str,
        args: list,
        kwargs: dict
    ) -> dict:
        """
        Call a module-level function.

        Args:
            module_path: Python module (e.g., "json")
            function_name: Function name (e.g., "dumps")
            args: Positional arguments
            kwargs: Keyword arguments

        Returns:
            dict: {"success": true, "result": <value>}
        """
        # Import module
        module = importlib.import_module(module_path)

        # Get function
        func = getattr(module, function_name)

        # Call function
        result = func(*args, **kwargs)

        return {
            "success": True,
            "result": result
        }
