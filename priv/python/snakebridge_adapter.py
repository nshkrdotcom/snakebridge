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
import time
import threading
from contextlib import nullcontext
from typing import Any, Dict, List, Tuple, Optional

# Import the SnakeBridge type encoding system
try:
    from snakebridge_types import decode, encode, encode_error
except ImportError:
    # If running as a script, try relative import
    import os
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from snakebridge_types import decode, encode, encode_error

try:
    from snakepit_bridge import telemetry as snakepit_telemetry
except Exception:
    snakepit_telemetry = None


# Module cache to avoid repeated imports
_module_cache: Dict[str, Any] = {}
_instance_registry: Dict[str, Any] = {}
_helper_registry: Dict[str, Any] = {}
_helper_registry_key: Optional[Tuple[Any, ...]] = None
_helper_registry_index: List[Dict[str, Any]] = []

# Thread locks for global state
_module_cache_lock = threading.RLock()
_registry_lock = threading.RLock()
_helper_lock = threading.RLock()

PROTOCOL_VERSION = 1
MIN_SUPPORTED_VERSION = 1
REF_SCHEMA_VERSION = 1
DEFAULT_REF_TTL_SECONDS = 0.0
DEFAULT_REF_MAX_SIZE = 10000
ALLOW_LEGACY_PROTOCOL = os.getenv("SNAKEBRIDGE_ALLOW_LEGACY_PROTOCOL", "false").lower() in (
    "1",
    "true",
    "yes",
)


class SnakeBridgeHelperNotFoundError(Exception):
    pass


class SnakeBridgeHelperLoadError(Exception):
    pass


class SnakeBridgeSerializationError(Exception):
    pass


class SnakeBridgeProtocolError(Exception):
    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None):
        super().__init__(message)
        self.details = details or {}


def _protocol_compatibility(arguments: Dict[str, Any]) -> None:
    protocol_version = arguments.get("protocol_version")
    min_supported_version = arguments.get("min_supported_version")

    if protocol_version is None and min_supported_version is None and ALLOW_LEGACY_PROTOCOL:
        protocol_version = MIN_SUPPORTED_VERSION
        min_supported_version = 0
    else:
        if protocol_version is None:
            protocol_version = 0
        if min_supported_version is None:
            min_supported_version = 0

    if protocol_version < MIN_SUPPORTED_VERSION or min_supported_version > PROTOCOL_VERSION:
        details = {
            "caller_protocol_version": protocol_version,
            "caller_min_supported_version": min_supported_version,
            "adapter_protocol_version": PROTOCOL_VERSION,
            "adapter_min_supported_version": MIN_SUPPORTED_VERSION,
        }
        message = (
            "SnakeBridge protocol version mismatch "
            f"(caller_protocol_version={protocol_version}, "
            f"caller_min_supported_version={min_supported_version}, "
            f"adapter_protocol_version={PROTOCOL_VERSION}, "
            f"adapter_min_supported_version={MIN_SUPPORTED_VERSION}). "
            "Ensure Elixir and Python SnakeBridge versions are compatible."
        )
        raise SnakeBridgeProtocolError(
            message,
            details=details,
        )


def _registry_limits() -> Tuple[float, int]:
    ttl_env = os.getenv("SNAKEBRIDGE_REF_TTL_SECONDS")
    max_env = os.getenv("SNAKEBRIDGE_REF_MAX")

    try:
        ttl = float(ttl_env) if ttl_env is not None else DEFAULT_REF_TTL_SECONDS
    except ValueError:
        ttl = DEFAULT_REF_TTL_SECONDS

    try:
        max_size = int(max_env) if max_env is not None else DEFAULT_REF_MAX_SIZE
    except ValueError:
        max_size = DEFAULT_REF_MAX_SIZE

    return ttl, max_size


def _entry_last_access(entry: Any) -> float:
    if isinstance(entry, dict):
        return float(entry.get("last_access") or entry.get("created_at") or 0.0)
    return 0.0


def _touch_entry(entry: Any) -> None:
    if isinstance(entry, dict):
        entry["last_access"] = time.time()


def _prune_registry() -> None:
    with _registry_lock:
        ttl_seconds, max_size = _registry_limits()
        now = time.time()

        if ttl_seconds and ttl_seconds > 0:
            for key, entry in list(_instance_registry.items()):
                if now - _entry_last_access(entry) > ttl_seconds:
                    del _instance_registry[key]

        if max_size and max_size > 0 and len(_instance_registry) > max_size:
            overflow = len(_instance_registry) - max_size
            oldest = sorted(_instance_registry.items(), key=lambda item: _entry_last_access(item[1]))
            for key, _entry in oldest[:overflow]:
                del _instance_registry[key]


def _store_ref(key: str, obj: Any) -> None:
    now = time.time()
    with _registry_lock:
        _instance_registry[key] = {"obj": obj, "created_at": now, "last_access": now}


def _extract_ref_identity(ref: dict, session_id: str) -> Tuple[str, str]:
    if ref.get("__type__") == "ref":
        ref_id = ref.get("id") or ref.get("ref_id")
        ref_session = ref.get("session_id") or session_id
    elif ref.get("__snakebridge_ref__"):
        ref_id = ref.get("ref_id")
        ref_session = ref.get("session_id") or session_id
    else:
        raise ValueError("Invalid SnakeBridge reference payload")

    if not ref_id:
        raise ValueError("SnakeBridge reference missing id")

    if ref_session and session_id and ref_session != session_id:
        raise ValueError("SnakeBridge reference session mismatch")

    return ref_id, ref_session

def _call_telemetry_span(metadata: Dict[str, Any]):
    if snakepit_telemetry is None:
        return nullcontext()
    try:
        return snakepit_telemetry.span("python.call", metadata)
    except Exception:
        return nullcontext()


def _call_function_name(call_type: str, function: Optional[str], arguments: Dict[str, Any]) -> str:
    if function:
        return str(function)
    if call_type == "class":
        return str(arguments.get("class") or arguments.get("class_name") or "unknown")
    if call_type in ("get_attr", "set_attr", "module_attr"):
        return str(arguments.get("attr") or "unknown")
    if call_type == "helper":
        return str(arguments.get("helper") or "unknown")
    return "unknown"


def _call_metadata(
    call_type: str,
    library: Optional[str],
    python_module: Optional[str],
    function: Optional[str],
    arguments: Dict[str, Any],
) -> Dict[str, Any]:
    metadata = {
        "library": str(library or "unknown"),
        "function": _call_function_name(call_type, function, arguments),
        "call_type": str(call_type),
    }
    if python_module:
        metadata["python_module"] = str(python_module)
    return metadata


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
        try:
            mod = _import_module(module)
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
        library = module.split(".")[0] if module else "unknown"
        return {
            "success": True,
            "result": encode_result(result, "default", module, library),
        }

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
        try:
            mod = _import_module(module)
        except ImportError as e:
            return encode_error(ImportError(f"Failed to import module '{module}': {str(e)}"))

        # Get the attribute
        if not hasattr(mod, attribute):
            return encode_error(AttributeError(f"Module '{module}' has no attribute '{attribute}'"))

        value = getattr(mod, attribute)

        # Encode and return the value
        library = module.split(".")[0] if module else "unknown"
        return {
            "success": True,
            "result": encode_result(value, "default", module, library),
        }

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
        try:
            mod = _import_module(module)
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
        library = module.split(".")[0] if module else "unknown"
        return {
            "success": True,
            "result": encode_result(instance, "default", module, library),
        }

    except Exception as e:
        return encode_error(e)


def _import_module(module_name: str) -> Any:
    with _module_cache_lock:
        if module_name in _module_cache:
            return _module_cache[module_name]

        mod = importlib.import_module(module_name)
        _module_cache[module_name] = mod
        return mod


def _make_ref(session_id: str, obj: Any, python_module: str, library: str) -> dict:
    ref_id = uuid.uuid4().hex
    key = f"{session_id}:{ref_id}"
    _prune_registry()
    _store_ref(key, obj)

    return {
        "__type__": "ref",
        "__schema__": REF_SCHEMA_VERSION,
        "id": ref_id,
        "session_id": session_id,
        "python_module": python_module,
        "library": library,
    }

def _make_stream_ref(
    session_id: str,
    obj: Any,
    python_module: str,
    library: str,
    stream_type: str,
) -> dict:
    ref_id = uuid.uuid4().hex
    key = f"{session_id}:{ref_id}"
    _prune_registry()
    _store_ref(key, obj)

    return {
        "__type__": "stream_ref",
        "id": ref_id,
        "session_id": session_id,
        "python_module": python_module,
        "library": library,
        "stream_type": stream_type,
    }


def encode_result(result: Any, session_id: str, python_module: str, library: str) -> Any:
    encoded = encode(result)
    if isinstance(encoded, dict) and encoded.get("__needs_stream_ref__"):
        stream_type = encoded.get("__stream_type__") or "iterator"
        return _make_stream_ref(session_id, result, python_module, library, stream_type)
    if isinstance(encoded, dict) and encoded.get("__needs_ref__"):
        return _make_ref(session_id, result, python_module, library)
    return encoded


def _is_ref_payload(value: Any) -> bool:
    if not isinstance(value, dict):
        return False
    type_tag = value.get("__type__")
    if type_tag is not None:
        return type_tag == "ref"
    return "id" in value and ("session_id" in value or "ref_id" in value)


def _resolve_refs(value: Any, session_id: str) -> Any:
    if isinstance(value, dict):
        if _is_ref_payload(value):
            return _resolve_ref(value, session_id)
        return {k: _resolve_refs(v, session_id) for k, v in value.items()}
    if isinstance(value, list):
        return [_resolve_refs(item, session_id) for item in value]
    if isinstance(value, tuple):
        return tuple(_resolve_refs(item, session_id) for item in value)
    return value


def _resolve_ref(ref: dict, session_id: str) -> Any:
    if not isinstance(ref, dict):
        raise ValueError("Invalid SnakeBridge reference payload")

    with _registry_lock:
        _prune_registry()
        ref_id, ref_session = _extract_ref_identity(ref, session_id)
        key = f"{ref_session}:{ref_id}"

        if key not in _instance_registry:
            raise KeyError(f"Unknown SnakeBridge reference: {ref_id}")

        entry = _instance_registry[key]
        if isinstance(entry, dict):
            _touch_entry(entry)
            return entry.get("obj")
        return entry


def _release_ref(ref: dict, session_id: str) -> bool:
    if not isinstance(ref, dict):
        raise ValueError("Invalid SnakeBridge reference payload")

    with _registry_lock:
        _prune_registry()
        ref_id, ref_session = _extract_ref_identity(ref, session_id)
        key = f"{ref_session}:{ref_id}"

        if key in _instance_registry:
            del _instance_registry[key]
            return True
        return False


def _release_session(session_id: str) -> int:
    if not session_id:
        return 0

    with _registry_lock:
        removed = 0
        prefix = f"{session_id}:"
        for key in list(_instance_registry.keys()):
            if key.startswith(prefix):
                del _instance_registry[key]
                removed += 1

        return removed


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

    with _helper_lock:
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

        if tool_name not in [
            "snakebridge.call",
            "snakebridge.stream",
            "snakebridge.release_ref",
            "snakebridge.release_session",
        ]:
            raise AttributeError(f"Tool '{tool_name}' not supported by SnakeBridgeAdapter")

        if isinstance(arguments, dict):
            _protocol_compatibility(arguments)

        session_id = None
        if isinstance(arguments, dict) and arguments.get("session_id"):
            session_id = arguments.get("session_id")
        elif context is not None and hasattr(context, "session_id"):
            session_id = context.session_id
        elif self.session_context is not None:
            session_id = self.session_context.session_id
        else:
            session_id = "default"

        if tool_name == "snakebridge.release_ref":
            ref = arguments.get("ref") if isinstance(arguments, dict) else None
            if ref is None:
                raise ValueError("snakebridge.release_ref requires ref")
            return _release_ref(ref, session_id)

        if tool_name == "snakebridge.release_session":
            return _release_session(session_id)

        call_type = arguments.get("call_type") or "function"
        module_path = arguments.get("module_path")
        python_module = arguments.get("python_module") or arguments.get("module")
        function = arguments.get("function")
        args = arguments.get("args") or []
        kwargs = arguments.get("kwargs") or {}
        if call_type == "dynamic" and not python_module:
            python_module = module_path
        library = arguments.get("library") or (python_module.split(".")[0] if python_module else None)
        if call_type not in ("helper", "stream_next") and not python_module:
            raise ValueError("snakebridge.call requires python_module")
        if not python_module:
            python_module = library or "unknown"
        if not library:
            library = python_module.split(".")[0] if python_module else "unknown"
        metadata = _call_metadata(call_type, library, python_module, function, arguments)
        decoded_args = [decode(item, session_id=session_id, context=context) for item in args]
        decoded_kwargs = {
            key: decode(value, session_id=session_id, context=context) for key, value in kwargs.items()
        }
        decoded_args = [_resolve_refs(item, session_id) for item in decoded_args]
        decoded_kwargs = {key: _resolve_refs(value, session_id) for key, value in decoded_kwargs.items()}

        with _call_telemetry_span(metadata):
            if call_type == "stream_next":
                stream_ref_payload = arguments.get("stream_ref")
                if stream_ref_payload is None:
                    raise ValueError("snakebridge.call requires stream_ref for stream_next")

                stream_ref = decode(stream_ref_payload, session_id=session_id, context=context)
                iterator = _resolve_ref(stream_ref, session_id)
                python_module = ""
                library = ""

                if isinstance(stream_ref_payload, dict):
                    python_module = stream_ref_payload.get("python_module", "") or ""
                    library = stream_ref_payload.get("library", "") or ""

                try:
                    item = next(iterator)
                    return encode_result(item, session_id, python_module, library)
                except StopIteration:
                    return {"__type__": "stop_iteration"}

            if call_type == "dynamic":
                module_path = arguments.get("module_path") or python_module
                if not module_path:
                    raise ValueError("snakebridge.call requires module_path for dynamic calls")
                mod = _import_module(module_path)
                func = getattr(mod, function)
                result = func(*decoded_args, **decoded_kwargs)
                return encode_result(result, session_id, module_path, library)

            if call_type == "class":
                class_name = arguments.get("class") or arguments.get("class_name")
                mod = _import_module(python_module)
                cls = getattr(mod, class_name)
                instance = cls(*decoded_args, **decoded_kwargs)
                return encode_result(instance, session_id, python_module, library)

            if call_type == "method":
                instance_payload = arguments.get("instance")
                instance = _resolve_ref(decode(instance_payload), session_id)
                method = getattr(instance, function)
                result = method(*decoded_args, **decoded_kwargs)
                return encode_result(result, session_id, python_module, library)

            if call_type == "get_attr":
                instance_payload = arguments.get("instance")
                instance = _resolve_ref(decode(instance_payload), session_id)
                attr = arguments.get("attr") or function
                result = getattr(instance, attr)
                return encode_result(result, session_id, python_module, library)

            if call_type == "module_attr":
                attr = arguments.get("attr") or function
                mod = _import_module(python_module)
                result = getattr(mod, attr)
                return encode_result(result, session_id, python_module, library)

            if call_type == "set_attr":
                instance_payload = arguments.get("instance")
                instance = _resolve_ref(decode(instance_payload), session_id)
                attr = arguments.get("attr") or function
                value = decoded_args[0] if decoded_args else None
                setattr(instance, attr, value)
                return encode_result(True, session_id, python_module, library)

            if call_type == "helper":
                helper_name = arguments.get("helper") or function
                helper_config = arguments.get("helper_config") or {}

                if not helper_name:
                    raise SnakeBridgeHelperNotFoundError("Helper name is required")

                registry = _load_helper_registry(helper_config)
                if helper_name not in registry:
                    raise SnakeBridgeHelperNotFoundError(f"Helper '{helper_name}' not found")

                result = registry[helper_name](*decoded_args, **decoded_kwargs)
                return encode_result(result, session_id, python_module, library)

            mod = _import_module(python_module)
            func = getattr(mod, function)
            result = func(*decoded_args, **decoded_kwargs)
            return encode_result(result, session_id, python_module, library)


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
