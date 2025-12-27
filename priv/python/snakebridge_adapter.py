"""
SnakeBridge Snakepit Adapter

Provides the Snakepit adapter interface for SnakeBridge.
This module is called by the Snakepit runtime to execute Python functions
and return results to Elixir.

Main function:
    snakebridge_call(module: str, function: str, args: dict) -> dict

The adapter:
1. Imports the specified Python module
2. Gets the specified function from the module
3. Decodes the arguments from SnakeBridge format
4. Calls the function with the decoded arguments
5. Encodes the result back to SnakeBridge format
6. Returns a success/error response
"""

import sys
import importlib
import inspect
import traceback
import uuid
import os
import glob
import hashlib
from typing import Any, Dict, List, Tuple, Optional

# Import the SnakeBridge type encoding system
try:
    from snakebridge_types import decode, encode, encode_result, encode_error
except ImportError:
    # If running as a script, try relative import
    import os
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from snakebridge_types import decode, encode, encode_result, encode_error


# Module cache to avoid repeated imports
_module_cache: Dict[str, Any] = {}
_instance_registry: Dict[str, Any] = {}
_helper_registry: Dict[str, Any] = {}
_helper_registry_key: Optional[Tuple[Any, ...]] = None
_helper_registry_index: List[Dict[str, Any]] = []


class SnakeBridgeHelperNotFoundError(Exception):
    pass


class SnakeBridgeHelperLoadError(Exception):
    pass


class SnakeBridgeSerializationError(Exception):
    pass


def snakebridge_call(module: str, function: str, args: dict) -> dict:
    """
    Call a Python function from SnakeBridge.

    This is the main entry point called by the Snakepit adapter.

    Args:
        module: The Python module name (e.g., 'math', 'numpy')
        function: The function name to call (e.g., 'sqrt', 'array')
        args: Dictionary of argument names to values (in SnakeBridge encoded format)

    Returns:
        Dictionary with either:
            - {"success": True, "result": <encoded_result>}
            - {"success": False, "error": <error_message>, "error_type": <error_type>}

    Examples:
        >>> snakebridge_call('math', 'sqrt', {'x': 16})
        {'success': True, 'result': 4.0}

        >>> snakebridge_call('math', 'gcd', {'a': 48, 'b': 18})
        {'success': True, 'result': 6}

        >>> snakebridge_call('statistics', 'mean', {'data': [1, 2, 3, 4, 5]})
        {'success': True, 'result': 3.0}
    """
    try:
        # Import the module (use cache if available)
        if module in _module_cache:
            mod = _module_cache[module]
        else:
            try:
                mod = importlib.import_module(module)
                _module_cache[module] = mod
            except ImportError as e:
                return encode_error(ImportError(f"Failed to import module '{module}': {str(e)}"))

        # Get the function from the module
        if not hasattr(mod, function):
            return encode_error(AttributeError(f"Module '{module}' has no function '{function}'"))

        func = getattr(mod, function)

        # Check if it's callable
        if not callable(func):
            return encode_error(TypeError(f"'{module}.{function}' is not callable"))

        # Decode arguments from SnakeBridge format
        try:
            decoded_args = {name: decode(value) for name, value in args.items()}
        except Exception as e:
            return encode_error(ValueError(f"Failed to decode arguments: {str(e)}"))

        # Call the function
        # Try to determine if we should use positional or keyword arguments
        try:
            # First, try with keyword arguments (most flexible)
            try:
                result = func(**decoded_args)
            except TypeError as e:
                error_msg = str(e)
                # If it fails because it doesn't accept keyword arguments,
                # try with positional arguments instead
                if "keyword argument" in error_msg.lower():
                    # Try to get the signature to determine argument order
                    try:
                        sig = inspect.signature(func)
                        # Create positional args in parameter order
                        positional_args = []
                        for param_name in sig.parameters.keys():
                            if param_name in decoded_args:
                                positional_args.append(decoded_args[param_name])

                        # If we didn't find any matching parameters, it might be a *args function
                        # Fall back to using values in insertion order
                        if not positional_args:
                            positional_args = list(decoded_args.values())

                        result = func(*positional_args)
                    except (ValueError, TypeError):
                        # Can't get signature, use values in insertion order (Python 3.7+ dicts)
                        positional_args = list(decoded_args.values())
                        result = func(*positional_args)
                else:
                    # Re-raise if it's a different kind of TypeError
                    raise
        except TypeError as e:
            # Provide helpful error message for argument mismatches
            error_msg = str(e)
            return encode_error(TypeError(f"Argument error calling {module}.{function}: {error_msg}"))
        except Exception as e:
            # Return any exception from the function call
            return encode_error(e)

        # Encode and return the result
        return encode_result(result)

    except Exception as e:
        # Catch any unexpected errors
        error_info = {
            "success": False,
            "error": str(e),
            "error_type": type(e).__name__,
            "traceback": traceback.format_exc()
        }
        return error_info


def snakebridge_batch_call(calls: list) -> list:
    """
    Execute multiple function calls in a batch.

    Args:
        calls: List of call specifications, each with 'module', 'function', and 'args'

    Returns:
        List of results corresponding to each call

    Example:
        >>> snakebridge_batch_call([
        ...     {'module': 'math', 'function': 'sqrt', 'args': {'x': 16}},
        ...     {'module': 'math', 'function': 'gcd', 'args': {'a': 48, 'b': 18}}
        ... ])
        [{'success': True, 'result': 4.0}, {'success': True, 'result': 6}]
    """
    results = []
    for call in calls:
        try:
            module = call['module']
            function = call['function']
            args = call.get('args', {})
            result = snakebridge_call(module, function, args)
            results.append(result)
        except Exception as e:
            results.append(encode_error(e))
    return results


def snakebridge_get_attribute(module: str, attribute: str) -> dict:
    """
    Get an attribute or constant from a module.

    Args:
        module: The Python module name
        attribute: The attribute name to get

    Returns:
        Dictionary with either:
            - {"success": True, "result": <encoded_value>}
            - {"success": False, "error": <error_message>}

    Example:
        >>> snakebridge_get_attribute('math', 'pi')
        {'success': True, 'result': 3.141592653589793}
    """
    try:
        # Import the module
        if module in _module_cache:
            mod = _module_cache[module]
        else:
            try:
                mod = importlib.import_module(module)
                _module_cache[module] = mod
            except ImportError as e:
                return encode_error(ImportError(f"Failed to import module '{module}': {str(e)}"))

        # Get the attribute
        if not hasattr(mod, attribute):
            return encode_error(AttributeError(f"Module '{module}' has no attribute '{attribute}'"))

        value = getattr(mod, attribute)

        # Encode and return the value
        return encode_result(value)

    except Exception as e:
        return encode_error(e)


def snakebridge_create_instance(module: str, class_name: str, args: dict) -> dict:
    """
    Create an instance of a class.

    Args:
        module: The Python module name
        class_name: The class name to instantiate
        args: Dictionary of constructor arguments

    Returns:
        Dictionary with either success or error

    Note:
        Instance objects cannot be serialized, so this is mainly useful
        for testing or when combined with a session/state system.
    """
    try:
        # Import the module
        if module in _module_cache:
            mod = _module_cache[module]
        else:
            try:
                mod = importlib.import_module(module)
                _module_cache[module] = mod
            except ImportError as e:
                return encode_error(ImportError(f"Failed to import module '{module}': {str(e)}"))

        # Get the class
        if not hasattr(mod, class_name):
            return encode_error(AttributeError(f"Module '{module}' has no class '{class_name}'"))

        cls = getattr(mod, class_name)

        # Check if it's a class
        if not isinstance(cls, type):
            return encode_error(TypeError(f"'{module}.{class_name}' is not a class"))

        # Decode arguments
        decoded_args = {name: decode(value) for name, value in args.items()}

        # Create instance
        instance = cls(**decoded_args)

        # Encode and return (note: complex objects may not serialize well)
        return encode_result(instance)

    except Exception as e:
        return encode_error(e)


def _import_module(module_name: str) -> Any:
    if module_name in _module_cache:
        return _module_cache[module_name]

    mod = importlib.import_module(module_name)
    _module_cache[module_name] = mod
    return mod


def _make_ref(session_id: str, obj: Any, python_module: str, library: str) -> dict:
    ref_id = uuid.uuid4().hex
    key = f"{session_id}:{ref_id}"
    _instance_registry[key] = obj

    return {
        "__snakebridge_ref__": True,
        "ref_id": ref_id,
        "session_id": session_id,
        "python_module": python_module,
        "library": library
    }


def _resolve_ref(ref: dict, session_id: str) -> Any:
    if not isinstance(ref, dict) or not ref.get("__snakebridge_ref__"):
        raise ValueError("Invalid SnakeBridge reference payload")

    ref_id = ref.get("ref_id")
    ref_session = ref.get("session_id") or session_id
    key = f"{ref_session}:{ref_id}"

    if key not in _instance_registry:
        raise KeyError(f"Unknown SnakeBridge reference: {ref_id}")

    return _instance_registry[key]


def _default_helper_config() -> Dict[str, Any]:
    return {
        "helper_paths": ["priv/python/helpers"],
        "helper_pack_enabled": True,
        "helper_allowlist": "all"
    }


def _normalize_helper_config(config: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    normalized = _default_helper_config()
    if isinstance(config, dict):
        normalized.update(config)

    helper_paths = normalized.get("helper_paths") or []
    if isinstance(helper_paths, str):
        helper_paths = [helper_paths]

    helper_paths = [os.path.abspath(path) for path in helper_paths if path]
    normalized["helper_paths"] = helper_paths
    normalized["helper_pack_enabled"] = bool(normalized.get("helper_pack_enabled", True))

    allowlist = normalized.get("helper_allowlist", "all")
    if allowlist in [None, "all", ":all"]:
        normalized["helper_allowlist"] = "all"
    elif isinstance(allowlist, (list, tuple, set)):
        normalized["helper_allowlist"] = [str(item) for item in allowlist]
    else:
        normalized["helper_allowlist"] = [str(allowlist)]

    return normalized


def _helper_config_key(config: Dict[str, Any]) -> Tuple[Any, ...]:
    helper_paths = tuple(config.get("helper_paths", []))
    allowlist = config.get("helper_allowlist", "all")
    allowlist_key = "all" if allowlist == "all" else tuple(allowlist)

    return (helper_paths, allowlist_key, bool(config.get("helper_pack_enabled", True)))


def _resolve_helper_paths(config: Dict[str, Any]) -> List[str]:
    paths: List[str] = []
    if config.get("helper_pack_enabled", True):
        pack_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "helpers")
        paths.append(pack_path)

    paths.extend(config.get("helper_paths", []))
    return paths


def _list_helper_files(paths: List[str]) -> List[str]:
    files: List[str] = []
    for path in paths:
        if not path:
            continue
        if os.path.isdir(path):
            for file_path in sorted(glob.glob(os.path.join(path, "*.py"))):
                base = os.path.basename(file_path)
                if base == "__init__.py" or base.startswith("_"):
                    continue
                files.append(file_path)
        elif os.path.isfile(path):
            base = os.path.basename(path)
            if base != "__init__.py" and not base.startswith("_"):
                files.append(path)
    return files


def _import_helper_module(path: str) -> Any:
    module_name = f"snakebridge_helper_{hashlib.md5(path.encode('utf-8')).hexdigest()}"
    if module_name in sys.modules:
        return sys.modules[module_name]

    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise SnakeBridgeHelperLoadError(f"Unable to load helper module: {path}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    sys.modules[module_name] = module
    return module


def _extract_helpers_from_module(module: Any) -> Dict[str, Any]:
    if hasattr(module, "__snakebridge_helpers__"):
        helpers = getattr(module, "__snakebridge_helpers__")
    elif hasattr(module, "snakebridge_helpers"):
        helpers = module.snakebridge_helpers()
    elif hasattr(module, "HELPERS"):
        helpers = getattr(module, "HELPERS")
    else:
        return {}

    if not isinstance(helpers, dict):
        raise SnakeBridgeHelperLoadError("Helper registry must be a dict of name => callable")

    for name, func in helpers.items():
        if not isinstance(name, str):
            raise SnakeBridgeHelperLoadError("Helper names must be strings")
        if not callable(func):
            raise SnakeBridgeHelperLoadError(f"Helper '{name}' is not callable")

    return helpers


def _apply_allowlist(helpers: Dict[str, Any], allowlist: Any) -> Dict[str, Any]:
    if allowlist == "all":
        return helpers
    if not allowlist:
        return {}

    return {name: func for name, func in helpers.items() if name in allowlist}


def _load_helper_registry(config: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    global _helper_registry, _helper_registry_key, _helper_registry_index

    normalized = _normalize_helper_config(config)
    key = _helper_config_key(normalized)

    if key == _helper_registry_key:
        return _helper_registry

    registry: Dict[str, Any] = {}
    for path in _resolve_helper_paths(normalized):
        if not path or not os.path.exists(path):
            continue

        for file_path in _list_helper_files([path]):
            module = _import_helper_module(file_path)
            helpers = _extract_helpers_from_module(module)
            registry.update(helpers)

    registry = _apply_allowlist(registry, normalized.get("helper_allowlist", "all"))
    _helper_registry = registry
    _helper_registry_key = key
    _helper_registry_index = _build_helper_index(registry)

    return registry


def _format_annotation(annotation: Any) -> Optional[str]:
    if annotation is inspect.Signature.empty:
        return None
    if hasattr(annotation, "__name__"):
        return annotation.__name__
    return str(annotation)


def _param_info(param: inspect.Parameter) -> Dict[str, Any]:
    info: Dict[str, Any] = {"name": param.name, "kind": param.kind.name}
    if param.default is not inspect.Parameter.empty:
        info["default"] = repr(param.default)
    if param.annotation is not inspect.Parameter.empty:
        info["annotation"] = _format_annotation(param.annotation)
    return info


def _build_helper_index(helpers: Dict[str, Any]) -> List[Dict[str, Any]]:
    index: List[Dict[str, Any]] = []
    for name, func in helpers.items():
        entry = {"name": name}

        try:
            sig = inspect.signature(func)
            entry["parameters"] = [_param_info(p) for p in sig.parameters.values()]
        except (ValueError, TypeError):
            entry["parameters"] = []

        doc = inspect.getdoc(func) or ""
        if doc:
            entry["docstring"] = doc[:8000]

        index.append(entry)

    index.sort(key=lambda item: item.get("name", ""))
    return index


def helper_registry_index(config: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
    _load_helper_registry(config or {})
    return _helper_registry_index


class SnakeBridgeAdapter:
    def __init__(self):
        self.session_context = None

    def set_session_context(self, session_context):
        self.session_context = session_context

    def execute_tool(self, tool_name: str, arguments: dict, context):
        if tool_name == "snakebridge.helpers":
            helper_config = {}
            if isinstance(arguments, dict):
                helper_config = arguments.get("helper_config") or arguments
            return helper_registry_index(helper_config)

        if tool_name not in ["snakebridge.call", "snakebridge.stream"]:
            raise AttributeError(f"Tool '{tool_name}' not supported by SnakeBridgeAdapter")

        session_id = None
        if context is not None and hasattr(context, "session_id"):
            session_id = context.session_id
        elif self.session_context is not None:
            session_id = self.session_context.session_id
        else:
            session_id = "default"

        call_type = arguments.get("call_type") or "function"
        python_module = arguments.get("python_module") or arguments.get("module")
        function = arguments.get("function")
        args = arguments.get("args") or []
        kwargs = arguments.get("kwargs") or {}
        library = arguments.get("library") or (python_module.split(".")[0] if python_module else None)

        if call_type == "class":
            class_name = arguments.get("class") or arguments.get("class_name")
            mod = _import_module(python_module)
            cls = getattr(mod, class_name)
            instance = cls(*args, **kwargs)
            return _make_ref(session_id, instance, python_module, library)

        if call_type == "method":
            instance = _resolve_ref(arguments.get("instance"), session_id)
            method = getattr(instance, function)
            return method(*args, **kwargs)

        if call_type == "get_attr":
            instance = _resolve_ref(arguments.get("instance"), session_id)
            attr = arguments.get("attr") or function
            return getattr(instance, attr)

        if call_type == "set_attr":
            instance = _resolve_ref(arguments.get("instance"), session_id)
            attr = arguments.get("attr") or function
            value = args[0] if args else None
            setattr(instance, attr, value)
            return True

        if call_type == "helper":
            helper_name = arguments.get("helper") or function
            helper_config = arguments.get("helper_config") or {}

            if not helper_name:
                raise SnakeBridgeHelperNotFoundError("Helper name is required")

            registry = _load_helper_registry(helper_config)
            if helper_name not in registry:
                raise SnakeBridgeHelperNotFoundError(f"Helper '{helper_name}' not found")

            return registry[helper_name](*args, **kwargs)

        if not python_module:
            raise ValueError("snakebridge.call requires python_module")

        mod = _import_module(python_module)
        func = getattr(mod, function)
        return func(*args, **kwargs)


# Make the module callable for testing
if __name__ == "__main__":
    import json

    # Simple test runner
    if len(sys.argv) > 1:
        # Test with command-line arguments
        # Usage: python snakebridge_adapter.py <module> <function> <json_args>
        if len(sys.argv) >= 4:
            module = sys.argv[1]
            function = sys.argv[2]
            args_json = sys.argv[3]
            args = json.loads(args_json)

            result = snakebridge_call(module, function, args)
            print(json.dumps(result, indent=2))
        else:
            print("Usage: python snakebridge_adapter.py <module> <function> <json_args>")
    else:
        # Run built-in tests
        print("Running SnakeBridge adapter tests...\n")

        # Test 1: math.sqrt
        print("Test 1: math.sqrt(16)")
        result = snakebridge_call('math', 'sqrt', {'x': 16})
        print(json.dumps(result, indent=2))
        assert result['success'] == True
        assert result['result'] == 4.0
        print("PASS\n")

        # Test 2: math.gcd
        print("Test 2: math.gcd(48, 18)")
        result = snakebridge_call('math', 'gcd', {'a': 48, 'b': 18})
        print(json.dumps(result, indent=2))
        assert result['success'] == True
        assert result['result'] == 6
        print("PASS\n")

        # Test 3: Error handling - module not found
        print("Test 3: Error handling - nonexistent module")
        result = snakebridge_call('nonexistent_module', 'func', {})
        print(json.dumps(result, indent=2))
        assert result['success'] == False
        print("PASS\n")

        # Test 4: Error handling - function not found
        print("Test 4: Error handling - nonexistent function")
        result = snakebridge_call('math', 'nonexistent_function', {})
        print(json.dumps(result, indent=2))
        assert result['success'] == False
        print("PASS\n")

        # Test 5: Complex types - tuple encoding
        print("Test 5: Complex types - math.gcd with large numbers")
        result = snakebridge_call('math', 'gcd', {'a': 1071, 'b': 462})
        print(json.dumps(result, indent=2))
        assert result['success'] == True
        assert result['result'] == 21
        print("PASS\n")

        # Test 6: Get attribute
        print("Test 6: Get math.pi")
        result = snakebridge_get_attribute('math', 'pi')
        print(json.dumps(result, indent=2))
        assert result['success'] == True
        assert abs(result['result'] - 3.141592653589793) < 0.0001
        print("PASS\n")

        print("All tests passed!")
