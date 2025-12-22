"""
SnakeBridge Python Adapter for Snakepit.

Provides dynamic Python library integration through introspection and
dynamic execution capabilities.
"""

import importlib
import inspect
import uuid
import time
import logging
import traceback
import threading
import typing
from typing import Any, Dict, List, Optional, get_type_hints

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


class InstanceManager:
    """
    Manages Python object instances with TTL-based cleanup.

    Instances are automatically cleaned up after they expire (default: 1 hour)
    based on their last access time.
    A background thread periodically removes expired instances.
    """

    def __init__(self, ttl_seconds: int = 3600, max_instances: int = 1000,
                 cleanup_interval: int = 60):
        """
        Initialize the instance manager.

        Args:
            ttl_seconds: Time-to-live for instances in seconds (default: 1 hour)
            max_instances: Maximum number of instances to store (default: 1000)
            cleanup_interval: How often to run cleanup in seconds (default: 60)
        """
        self.instances: Dict[str, tuple] = {}  # {id: (instance, created_at, last_accessed)}
        self.ttl = ttl_seconds
        self.max_instances = max_instances
        self.cleanup_interval = cleanup_interval
        self.lock = threading.Lock()
        self._shutdown = threading.Event()
        self._cleanup_thread: Optional[threading.Thread] = None
        self._start_cleanup_thread()

    def _start_cleanup_thread(self):
        """Start the background cleanup thread."""
        self._cleanup_thread = threading.Thread(
            target=self._cleanup_loop,
            daemon=True,
            name="InstanceManager-Cleanup"
        )
        self._cleanup_thread.start()
        logger.debug("Instance cleanup thread started")

    def _cleanup_loop(self):
        """Background loop that periodically cleans up expired instances."""
        while not self._shutdown.wait(self.cleanup_interval):
            try:
                self._cleanup_expired()
            except Exception as e:
                logger.error(f"Error during instance cleanup: {e}")

    def _cleanup_expired(self):
        """Remove expired instances."""
        now = time.time()
        with self.lock:
            expired = [
                id for id, (_, _, last_accessed) in self.instances.items()
                if now - last_accessed > self.ttl
            ]
            for id in expired:
                del self.instances[id]
                logger.debug(f"Cleaned up expired instance: {id}")

            if expired:
                logger.info(f"Cleaned up {len(expired)} expired instances")

    def _evict_oldest(self):
        """Evict the oldest instance when at capacity."""
        if not self.instances:
            return
        oldest_id = min(
            self.instances.keys(),
            key=lambda k: self.instances[k][1]  # created_at
        )
        del self.instances[oldest_id]
        logger.debug(f"Evicted oldest instance: {oldest_id}")

    def store(self, instance_id: str, instance: Any) -> None:
        """Store an instance with the given ID."""
        with self.lock:
            if len(self.instances) >= self.max_instances:
                self._evict_oldest()
            now = time.time()
            self.instances[instance_id] = (instance, now, now)
            logger.debug(f"Stored instance: {instance_id}")

    def get(self, instance_id: str) -> Any:
        """
        Get an instance by ID.

        Raises KeyError if instance not found or expired.
        """
        with self.lock:
            if instance_id not in self.instances:
                raise KeyError(f"Instance {instance_id} not found or expired")
            inst, created, _ = self.instances[instance_id]
            # Update last accessed time
            self.instances[instance_id] = (inst, created, time.time())
            return inst

    def remove(self, instance_id: str) -> bool:
        """Remove an instance by ID. Returns True if removed, False if not found."""
        with self.lock:
            if instance_id in self.instances:
                del self.instances[instance_id]
                logger.debug(f"Removed instance: {instance_id}")
                return True
            return False

    def shutdown(self):
        """Stop the cleanup thread and clear all instances."""
        self._shutdown.set()
        if self._cleanup_thread and self._cleanup_thread.is_alive():
            self._cleanup_thread.join(timeout=5)
        with self.lock:
            self.instances.clear()
        logger.info("Instance manager shut down")

    def __len__(self):
        """Return the number of stored instances."""
        with self.lock:
            return len(self.instances)


class SnakeBridgeAdapter(ThreadSafeAdapter):
    """
    Snakepit adapter for dynamic Python library integration.

    Provides tools:
    - describe_library: Introspect Python modules
    - call_python: Execute Python code dynamically

    Features:
    - TTL-based instance cleanup
    - Traceback reporting on errors
    - Recursion depth limiting for introspection
    - Type hint extraction
    """

    # Maximum depth for introspection to prevent infinite recursion
    MAX_INTROSPECTION_DEPTH = 5

    def __init__(self, ttl_seconds: int = 3600, max_instances: int = 1000):
        """Initialize adapter with instance storage."""
        if HAS_SNAKEPIT:
            super().__init__()
        self.instance_manager = InstanceManager(
            ttl_seconds=ttl_seconds,
            max_instances=max_instances
        )
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
        self.instance_manager.shutdown()
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
                "error": f"Unknown tool: {tool_name}",
                "traceback": None
            }

    @tool(description="Introspect Python module structure")
    def describe_library(self, module_path: str, discovery_depth: int = 2) -> dict:
        """
        Introspect a Python module and return its schema.

        Args:
            module_path: Python module path (e.g., "json", "dspy.Predict")
            discovery_depth: How deep to recurse into submodules (default: 2)

        Returns:
            dict: Schema with library_version, classes, functions, submodules
                {
                    "success": true/false,
                    "library_version": "x.y.z",
                    "classes": {...},
                    "functions": {...},
                    "submodules": [...],
                    "type_hints": {...},
                    "error": "..." (if failed),
                    "traceback": "..." (if failed)
                }
        """
        # Clamp discovery_depth to prevent infinite recursion
        discovery_depth = min(discovery_depth, self.MAX_INTROSPECTION_DEPTH)

        try:
            # Import the module
            module = importlib.import_module(module_path)

            # Extract version
            version = getattr(module, "__version__", "unknown")

            # Introspect functions
            functions = self._introspect_functions(module, module_path)

            # Introspect classes
            classes = self._introspect_classes(module, module_path, discovery_depth)

            # Introspect submodules
            submodules = self._introspect_submodules(module, module_path)

            # Extract type hints
            type_hints = self._extract_type_hints(module)

            return {
                "success": True,
                "library_version": version,
                "functions": functions,
                "classes": classes,
                "submodules": submodules,
                "type_hints": type_hints
            }

        except ModuleNotFoundError as e:
            return {
                "success": False,
                "error": str(e),
                "traceback": traceback.format_exc()
            }
        except Exception as e:
            logger.error(f"Error introspecting {module_path}: {e}")
            return {
                "success": False,
                "error": str(e),
                "traceback": traceback.format_exc()
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
            dict: Result or error with traceback
                {
                    "success": true/false,
                    "result": <value>,  (or "instance_id": <id> for __init__)
                    "error": "..." (if failed),
                    "traceback": "..." (if failed)
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
                "error": str(e),
                "traceback": traceback.format_exc()
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
                "parameters": self._get_function_parameters(obj),
                "return_type": self._get_return_type(obj)
            }

        return functions

    def _introspect_classes(self, module, module_path: str, depth: int) -> dict:
        """Introspect classes in module."""
        classes = {}

        if depth <= 0:
            return classes

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
                "methods": self._get_class_methods(obj, depth - 1),
                "constructor": self._get_constructor_info(obj),
                "properties": self._get_class_properties(obj)
            }

        return classes

    def _introspect_submodules(self, module, module_path: str) -> List[str]:
        """Get list of submodule names."""
        submodules = []

        try:
            # Check if module has __path__ (is a package)
            if hasattr(module, "__path__"):
                import pkgutil
                for importer, modname, ispkg in pkgutil.iter_modules(module.__path__):
                    submodules.append(f"{module_path}.{modname}")
        except Exception as e:
            logger.debug(f"Could not enumerate submodules for {module_path}: {e}")

        return submodules

    def _extract_type_hints(self, module) -> dict:
        """Extract typing information from annotations."""
        hints = {}

        for name, obj in inspect.getmembers(module):
            if name.startswith("_"):
                continue

            try:
                if hasattr(obj, "__annotations__"):
                    hints[name] = {
                        k: self._type_to_string(v)
                        for k, v in obj.__annotations__.items()
                    }
            except Exception:
                continue

        return hints

    def _type_to_string(self, type_hint) -> str:
        """Convert a type hint to a string representation."""
        if type_hint is None:
            return "None"

        # Handle typing module types
        origin = getattr(type_hint, "__origin__", None)
        if origin is not None:
            args = getattr(type_hint, "__args__", ())
            if args:
                args_str = ", ".join(self._type_to_string(a) for a in args)
                return f"{origin.__name__}[{args_str}]"
            return str(origin.__name__)

        # Handle regular types
        if hasattr(type_hint, "__name__"):
            return type_hint.__name__

        return str(type_hint)

    def _get_function_parameters(self, func) -> list:
        """Extract function parameters using inspect."""
        try:
            sig = inspect.signature(func)
            params = []

            # Get type hints if available
            try:
                hints = get_type_hints(func)
            except Exception:
                hints = {}

            for param_name, param in sig.parameters.items():
                param_info = {
                    "name": param_name,
                    "required": param.default == inspect.Parameter.empty,
                    "kind": str(param.kind.name).lower()
                }

                # Add default value if present
                if param.default != inspect.Parameter.empty:
                    try:
                        param_info["default"] = repr(param.default)
                    except Exception:
                        param_info["default"] = "..."

                # Add type hint if available
                if param_name in hints:
                    param_info["type"] = self._type_to_string(hints[param_name])
                elif param.annotation != inspect.Parameter.empty:
                    param_info["type"] = self._type_to_string(param.annotation)

                params.append(param_info)

            return params
        except (ValueError, TypeError):
            return []

    def _get_return_type(self, func) -> Optional[str]:
        """Extract return type from function."""
        try:
            hints = get_type_hints(func)
            if "return" in hints:
                return self._type_to_string(hints["return"])
        except Exception:
            pass

        try:
            sig = inspect.signature(func)
            if sig.return_annotation != inspect.Parameter.empty:
                return self._type_to_string(sig.return_annotation)
        except Exception:
            pass

        return None

    def _get_class_methods(self, cls, depth: int) -> list:
        """Extract methods from a class."""
        methods = []

        if depth < 0:
            return methods

        for name, obj in inspect.getmembers(cls):
            # Include __init__ and __call__, skip other private methods
            if name.startswith("_") and name not in ("__init__", "__call__"):
                continue

            # Only include methods (not properties, etc.)
            if not (inspect.isfunction(obj) or inspect.ismethod(obj)):
                continue

            methods.append({
                "name": name,
                "docstring": inspect.getdoc(obj) or "",
                "parameters": self._get_function_parameters(obj),
                "return_type": self._get_return_type(obj)
            })

        return methods

    def _get_constructor_info(self, cls) -> dict:
        """Get constructor information for a class."""
        try:
            init_method = getattr(cls, "__init__", None)
            if init_method:
                return {
                    "parameters": self._get_function_parameters(init_method),
                    "docstring": inspect.getdoc(init_method) or ""
                }
        except Exception:
            pass

        return {"parameters": [], "docstring": ""}

    def _get_class_properties(self, cls) -> list:
        """Get properties from a class."""
        properties = []

        for name, obj in inspect.getmembers(cls):
            if name.startswith("_"):
                continue

            if isinstance(obj, property):
                properties.append({
                    "name": name,
                    "docstring": inspect.getdoc(obj) or "",
                    "readonly": obj.fset is None
                })

        return properties

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
        try:
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
            self.instance_manager.store(instance_id, instance)

            logger.info(f"Created instance {instance_id} of {module_path}")

            return {
                "success": True,
                "instance_id": instance_id
            }
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "traceback": traceback.format_exc()
            }

    def _prepare_args(
        self,
        func,
        args: list,
        kwargs: dict
    ) -> tuple[list, dict]:
        """
        Normalize positional-only arguments when they are provided as kwargs.

        Some standard library functions (e.g., math.sqrt) declare positional-only
        parameters. Elixir calls often come through as kwargs, so we lift any
        positional-only kwargs into the args list in signature order while
        leaving keyword-only parameters intact.
        """
        if not kwargs:
            return args, kwargs

        try:
            signature = inspect.signature(func)
        except (ValueError, TypeError):
            return args, kwargs

        args_list = list(args)
        kwargs_copy = dict(kwargs)

        for name, param in signature.parameters.items():
            if param.kind == param.POSITIONAL_ONLY and name in kwargs_copy:
                args_list.append(kwargs_copy.pop(name))

        return args_list, kwargs_copy

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
        try:
            # Extract instance ID
            instance_id = instance_ref.replace("instance:", "")

            # Get instance
            instance = self.instance_manager.get(instance_id)

            # Call method
            method = getattr(instance, method_name)
            prepared_args, prepared_kwargs = self._prepare_args(method, args, kwargs)
            result = method(*prepared_args, **prepared_kwargs)

            # Handle generators
            if inspect.isgenerator(result):
                # Convert generator to list for JSON serialization
                result = list(result)

            return {
                "success": True,
                "result": result
            }
        except KeyError as e:
            return {
                "success": False,
                "error": str(e),
                "traceback": traceback.format_exc()
            }
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "traceback": traceback.format_exc()
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
        try:
            # Import module
            module = importlib.import_module(module_path)

            # Get function
            func = getattr(module, function_name)

            # Call function
            prepared_args, prepared_kwargs = self._prepare_args(func, args, kwargs)
            result = func(*prepared_args, **prepared_kwargs)

            # Handle generators
            if inspect.isgenerator(result):
                # Convert generator to list for JSON serialization
                result = list(result)

            return {
                "success": True,
                "result": result
            }
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "traceback": traceback.format_exc()
            }
