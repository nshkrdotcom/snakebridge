"""
SnakeBridge Type Encoding System

Provides encoding and decoding functions for converting between Python and Elixir types.
Uses tagged JSON format with __type__ markers for special types that don't map directly to JSON.

Supported special types:
- atom: Elixir atoms (encoded with __type__ tag)
- tuple: Python tuples (encoded as lists with __type__ tag)
- set: Python sets (encoded as lists with __type__ tag)
- frozenset: Python frozensets (encoded as lists with __type__ tag)
- bytes: Python bytes (encoded as base64 strings with __type__ tag)
- complex: Python complex numbers (encoded as [real, imag] with __type__ tag)
- datetime: datetime objects (encoded as ISO 8601 strings with __type__ tag)
- date: date objects (encoded as ISO 8601 strings with __type__ tag)
- time: time objects (encoded as ISO 8601 strings with __type__ tag)
- special_float: Positive infinity, negative infinity, and NaN (encoded with __type__ tag)
- dict: Tagged dict format for non-string keys (with pairs array)

Encoding safety:
- Non-JSON-serializable values return {"__needs_ref__": True, ...} marker
- Containers with unencodable items return __needs_ref__ marker for whole container
- Iterators/generators return {"__needs_stream_ref__": True, ...} marker
- This ensures NEVER returning partially-encoded or lossy representations
"""

import base64
import inspect
import json
import math
import os
import types
from datetime import datetime, date, time
from typing import Any, Dict, List, Union

SCHEMA_VERSION = 1

# Supported types for direct JSON encoding (primitives)
JSON_SAFE_PRIMITIVES = (type(None), bool, int, float, str)


class Atom:
    """Represents an Elixir atom value on the Python side."""

    def __init__(self, value: str):
        self.value = str(value)

    def __repr__(self) -> str:
        return f"Atom({self.value!r})"

    def __str__(self) -> str:
        return self.value


def _tag(type_tag: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    tagged = dict(payload)
    tagged["__type__"] = type_tag
    tagged["__schema__"] = SCHEMA_VERSION
    return tagged


def encode(value: Any) -> Any:
    """
    Encode a Python value to a JSON-safe value with __type__ tags for special types.

    Returns one of:
    - JSON-safe primitive (None, bool, int, float, str)
    - JSON-safe list (recursively encoded)
    - JSON-safe dict with string keys (recursively encoded)
    - Tagged value with __type__ key
    - Marker dict with __needs_ref__ = True (for ref-wrapping)
    - Marker dict with __needs_stream_ref__ = True (for iterators)

    NEVER returns partially-encoded or lossy representations.

    Args:
        value: The Python value to encode

    Returns:
        A JSON-safe value (possibly with __type__ tags)

    Examples:
        >>> encode((1, 2, 3))
        {'__type__': 'tuple', '__schema__': 1, 'elements': [1, 2, 3]}

        >>> encode({1, 2, 3})
        {'__type__': 'set', '__schema__': 1, 'elements': [1, 2, 3]}

        >>> encode(b'hello')
        {'__type__': 'bytes', '__schema__': 1, 'data': 'aGVsbG8='}

        >>> encode(1+2j)
        {'__type__': 'complex', '__schema__': 1, 'real': 1.0, 'imag': 2.0}
    """
    # Handle None
    if value is None:
        return None

    # Handle booleans (must check before int - bool is subclass of int)
    if isinstance(value, bool):
        return value

    # Handle integers
    if isinstance(value, int):
        return value

    # Handle float (check for special values)
    if isinstance(value, float):
        return _encode_float(value)

    # Handle strings
    if isinstance(value, str):
        return value

    # Handle bytes/bytearray - always tagged
    if isinstance(value, (bytes, bytearray)):
        return _tag("bytes", {"data": base64.b64encode(bytes(value)).decode("ascii")})

    # Handle tagged atoms
    if isinstance(value, Atom):
        return _tag("atom", {"value": value.value})

    # Handle tuple - check for unencodable items
    if isinstance(value, tuple):
        return _encode_tuple(value)

    # Handle frozenset - check for unencodable items
    if isinstance(value, frozenset):
        return _encode_frozenset(value)

    # Handle set - check for unencodable items
    if isinstance(value, set):
        return _encode_set(value)

    # Handle complex
    if isinstance(value, complex):
        return _tag("complex", {"real": value.real, "imag": value.imag})

    # Handle datetime types
    if isinstance(value, datetime):
        return _tag("datetime", {"value": value.isoformat()})
    if isinstance(value, date):
        return _tag("date", {"value": value.isoformat()})
    if isinstance(value, time):
        return _tag("time", {"value": value.isoformat()})

    # Handle list - check for unencodable items
    if isinstance(value, list):
        return _encode_list(value)

    # Handle dict - handle carefully (may need tagged format)
    if isinstance(value, dict):
        return _encode_dict(value)

    # Detect generators and iterators - need stream ref
    if _is_generator_or_iterator(value):
        return {
            "__needs_stream_ref__": True,
            "__stream_type__": _get_stream_type(value),
            "__type_name__": type(value).__name__,
            "__module__": type(value).__module__,
        }

    # EVERYTHING ELSE - needs a ref
    # This is the critical safety net
    return {
        "__needs_ref__": True,
        "__type_name__": type(value).__name__,
        "__module__": type(value).__module__,
    }


def _encode_float(value: float) -> Any:
    """Encode a float, handling special values."""
    if math.isinf(value):
        return _tag("special_float", {"value": "infinity" if value > 0 else "neg_infinity"})
    if math.isnan(value):
        return _tag("special_float", {"value": "nan"})
    return value


def _encode_tuple(value: tuple) -> Any:
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
                "__reason__": f"contains unencodable item of type {enc.get('__type_name__')}",
            }
        if isinstance(enc, dict) and enc.get("__needs_stream_ref__"):
            # Item needs stream ref - whole tuple needs ref
            return {
                "__needs_ref__": True,
                "__type_name__": "tuple",
                "__module__": "builtins",
                "__reason__": f"contains iterator/generator",
            }
        elements.append(enc)
    return _tag("tuple", {"elements": elements})


def _encode_set(value: set) -> Any:
    """Encode a set, checking for unencodable items."""
    elements = []
    try:
        sorted_values = sorted(value, key=lambda x: (type(x).__name__, str(x)))
    except TypeError:
        # If sorting fails, use unsorted
        sorted_values = list(value)
    for item in sorted_values:
        enc = encode(item)
        if isinstance(enc, dict) and enc.get("__needs_ref__"):
            return {
                "__needs_ref__": True,
                "__type_name__": "set",
                "__module__": "builtins",
                "__reason__": f"contains unencodable item of type {enc.get('__type_name__')}",
            }
        if isinstance(enc, dict) and enc.get("__needs_stream_ref__"):
            return {
                "__needs_ref__": True,
                "__type_name__": "set",
                "__module__": "builtins",
                "__reason__": f"contains iterator/generator",
            }
        elements.append(enc)
    return _tag("set", {"elements": elements})


def _encode_frozenset(value: frozenset) -> Any:
    """Encode a frozenset, checking for unencodable items."""
    elements = []
    try:
        sorted_values = sorted(value, key=lambda x: (type(x).__name__, str(x)))
    except TypeError:
        # If sorting fails, use unsorted
        sorted_values = list(value)
    for item in sorted_values:
        enc = encode(item)
        if isinstance(enc, dict) and enc.get("__needs_ref__"):
            return {
                "__needs_ref__": True,
                "__type_name__": "frozenset",
                "__module__": "builtins",
                "__reason__": f"contains unencodable item of type {enc.get('__type_name__')}",
            }
        if isinstance(enc, dict) and enc.get("__needs_stream_ref__"):
            return {
                "__needs_ref__": True,
                "__type_name__": "frozenset",
                "__module__": "builtins",
                "__reason__": f"contains iterator/generator",
            }
        elements.append(enc)
    return _tag("frozenset", {"elements": elements})


def _encode_list(lst: list) -> Any:
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
                "__reason__": f"contains unencodable item of type {enc.get('__type_name__')}",
            }
        if isinstance(enc, dict) and enc.get("__needs_stream_ref__"):
            # Item is an iterator - whole list needs ref-wrapping
            return {
                "__needs_ref__": True,
                "__type_name__": "list",
                "__module__": "builtins",
                "__reason__": "contains iterator/generator",
            }
        encoded.append(enc)
    return encoded


def _encode_dict(d: dict) -> Any:
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
        return _encode_string_key_dict(d)
    else:
        return _encode_tagged_dict(d)


def _encode_string_key_dict(d: dict) -> Any:
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
                "__reason__": f"contains unencodable value for key '{k}'",
            }
        if isinstance(enc_v, dict) and enc_v.get("__needs_stream_ref__"):
            return {
                "__needs_ref__": True,
                "__type_name__": "dict",
                "__module__": "builtins",
                "__reason__": f"contains iterator/generator for key '{k}'",
            }
        encoded[k] = enc_v
    return encoded


def _encode_tagged_dict(d: dict) -> Any:
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
                "__reason__": "contains unencodable key",
            }
        if isinstance(enc_k, dict) and enc_k.get("__needs_stream_ref__"):
            return {
                "__needs_ref__": True,
                "__type_name__": "dict",
                "__module__": "builtins",
                "__reason__": "key is iterator/generator",
            }
        if isinstance(enc_v, dict) and enc_v.get("__needs_ref__"):
            return {
                "__needs_ref__": True,
                "__type_name__": "dict",
                "__module__": "builtins",
                "__reason__": "contains unencodable value",
            }
        if isinstance(enc_v, dict) and enc_v.get("__needs_stream_ref__"):
            return {
                "__needs_ref__": True,
                "__type_name__": "dict",
                "__module__": "builtins",
                "__reason__": "value is iterator/generator",
            }

        pairs.append([enc_k, enc_v])

    return _tag("dict", {"pairs": pairs})


def _is_generator_or_iterator(value: Any) -> bool:
    """Check if value is a generator or iterator."""
    if isinstance(value, types.GeneratorType):
        return True
    # Check for async generators if available
    if hasattr(types, 'AsyncGeneratorType') and isinstance(value, types.AsyncGeneratorType):
        return True
    # Check for iterator protocol
    if hasattr(value, '__next__') and hasattr(value, '__iter__'):
        # Exclude basic iterable types and context managers (file handles)
        if isinstance(value, (str, bytes, bytearray, list, tuple, dict, set, frozenset)):
            return False
        # Prefer regular refs for context managers (e.g. file objects)
        if hasattr(value, "__enter__") and hasattr(value, "__exit__"):
            return False
        return True
    return False


def _get_stream_type(value: Any) -> str:
    """Determine stream type for iterator/generator."""
    if isinstance(value, types.GeneratorType):
        return "generator"
    if hasattr(types, 'AsyncGeneratorType') and isinstance(value, types.AsyncGeneratorType):
        return "async_generator"
    return "iterator"


def encode_dict(d: Dict[Any, Any]) -> Dict[str, Any]:
    """
    Encode a dictionary.

    If all keys are strings, returns a plain dict (JSON object).
    If any key is not a string, returns a tagged dict with pairs.
    If any value is unencodable, returns __needs_ref__ marker.

    DEPRECATED: Use _encode_dict() internally. This wrapper is kept for backwards compatibility.

    Args:
        d: The dictionary to encode

    Returns:
        Either a plain dict, a tagged dict with pairs, or __needs_ref__ marker
    """
    return _encode_dict(d)


def encode_dict_key(key: Any) -> str:
    """
    Encode a dictionary key to a string.

    DEPRECATED: This function is kept for backwards compatibility but
    is no longer used for dict encoding. Use encode_dict() instead.

    Args:
        key: The dictionary key to encode

    Returns:
        A string representation of the key
    """
    if isinstance(key, str):
        return key
    elif isinstance(key, (int, float, bool)):
        return str(key)
    elif isinstance(key, tuple):
        return str(key)
    else:
        return repr(key)


def decode(value: Any, session_id: str = None, context: Any = None) -> Any:
    """
    Decode a JSON value with __type__ tags back to Python values.

    Args:
        value: The JSON value to decode (possibly with __type__ tags)

    Returns:
        The decoded Python value

    Examples:
        >>> decode({'__type__': 'tuple', '__schema__': 1, 'elements': [1, 2, 3]})
        (1, 2, 3)

        >>> decode({'__type__': 'set', '__schema__': 1, 'elements': [1, 2, 3]})
        {1, 2, 3}

        >>> decode({'__type__': 'bytes', '__schema__': 1, 'data': 'aGVsbG8='})
        b'hello'

        >>> decode({'__type__': 'complex', '__schema__': 1, 'real': 1.0, 'imag': 2.0})
        (1+2j)
    """
    # Handle None
    if value is None:
        return None

    # Handle basic types
    if isinstance(value, (bool, int, float, str)):
        return value

    # Handle list
    if isinstance(value, list):
        return [decode(item, session_id=session_id, context=context) for item in value]

    # Handle dict (check for __type__ tag)
    if isinstance(value, dict):
        if "__type__" in value:
            type_tag = value["__type__"]

            if type_tag == "atom":
                # Default: return plain string for library compatibility
                # Opt-in to Atom class via SNAKEBRIDGE_ATOM_CLASS=true
                atom_value = value.get("value", "")
                if os.environ.get("SNAKEBRIDGE_ATOM_CLASS", "").lower() in (
                    "true",
                    "1",
                    "yes",
                ):
                    return Atom(atom_value)
                return atom_value

            if type_tag == "tuple":
                elements = value.get("elements") or value.get("value") or []
                return tuple(decode(item, session_id=session_id, context=context) for item in elements)

            elif type_tag == "set":
                elements = value.get("elements") or value.get("value") or []
                return set(decode(item, session_id=session_id, context=context) for item in elements)

            elif type_tag == "frozenset":
                elements = value.get("elements") or value.get("value") or []
                return frozenset(decode(item, session_id=session_id, context=context) for item in elements)

            elif type_tag == "bytes":
                data = value.get("data") or value.get("value")
                if data is None:
                    return value
                return base64.b64decode(data)

            elif type_tag == "complex":
                return complex(value["real"], value["imag"])

            elif type_tag == "datetime":
                return datetime.fromisoformat(value["value"])

            elif type_tag == "date":
                return date.fromisoformat(value["value"])

            elif type_tag == "time":
                return time.fromisoformat(value["value"])

            elif type_tag == "special_float":
                special = value.get("value")
                if special == "infinity":
                    return float("inf")
                if special == "neg_infinity":
                    return float("-inf")
                if special == "nan":
                    return float("nan")
                return value

            elif type_tag == "infinity":
                return float("inf")

            elif type_tag == "neg_infinity":
                return float("-inf")

            elif type_tag == "nan":
                return float("nan")

            elif type_tag == "callback":
                return _decode_callback(value, session_id, context)

            elif type_tag == "dict":
                return decode_tagged_dict(value, session_id, context)

            else:
                # Unknown type tag, return as-is
                return {k: decode(v, session_id=session_id, context=context) for k, v in value.items()}
        else:
            # Regular dict, decode recursively
            return {k: decode(v, session_id=session_id, context=context) for k, v in value.items()}

    # Return as-is for any other type
    return value


def decode_tagged_dict(value: Dict[str, Any], session_id: str = None, context: Any = None) -> Dict[Any, Any]:
    """
    Decode a tagged dict with potentially non-string keys.

    Args:
        value: The tagged dict value with "pairs" key
        session_id: Optional session ID for ref decoding
        context: Optional context for callback decoding

    Returns:
        A Python dict with decoded keys and values
    """
    pairs = value.get("pairs", [])
    result = {}

    for pair in pairs:
        if isinstance(pair, list) and len(pair) == 2:
            key = decode(pair[0], session_id=session_id, context=context)
            val = decode(pair[1], session_id=session_id, context=context)
            result[key] = val

    return result


def _decode_callback(value: Dict[str, Any], session_id: str, context: Any):
    callback_id = value.get("ref_id") or value.get("callback_id")
    arity = value.get("arity")

    def _encode_any_json(payload):
        from google.protobuf import any_pb2

        any_value = any_pb2.Any()
        any_value.type_url = "type.googleapis.com/google.protobuf.StringValue"
        any_value.value = json.dumps(payload).encode("utf-8")
        return any_value

    def _callback(*args):
        if arity is not None and len(args) != arity:
            raise TypeError(f"Callback expected arity {arity}, got {len(args)}")

        if context is None or not hasattr(context, "stub"):
            raise RuntimeError("Elixir callback invoked without session context")

        callback_session_id = session_id or getattr(context, "session_id", None) or "default"
        encoded_args = [encode(arg) for arg in args]

        try:
            from snakepit_bridge_pb2 import ExecuteElixirToolRequest
            from snakepit_bridge.serialization import TypeSerializer
        except Exception as exc:
            raise RuntimeError(f"Callback bridge unavailable: {exc}") from exc

        request = ExecuteElixirToolRequest(
            session_id=callback_session_id,
            tool_name="snakebridge.callback",
            parameters={
                "callback_id": _encode_any_json(callback_id),
                "args": _encode_any_json(encoded_args),
            },
        )

        response = context.stub.ExecuteElixirTool(request)

        if not getattr(response, "success", False):
            error_message = getattr(response, "error_message", "callback failed")
            raise RuntimeError(f"Callback failed: {error_message}")

        binary_result = getattr(response, "binary_result", None) or None
        result = TypeSerializer.decode_any(response.result, binary_result)

        if isinstance(result, dict) and result.get("__type__") == "callback_error":
            raise RuntimeError(result.get("reason", "callback_error"))

        return decode(result, session_id=callback_session_id, context=context)

    return _callback


# Convenience functions for common operations
def encode_args(args: Dict[str, Any]) -> Dict[str, Any]:
    """
    Encode a dictionary of function arguments.

    Args:
        args: Dictionary of argument names to values

    Returns:
        Dictionary with encoded values
    """
    return {name: encode(value) for name, value in args.items()}


def decode_args(args: Dict[str, Any]) -> Dict[str, Any]:
    """
    Decode a dictionary of function arguments.

    Args:
        args: Dictionary of argument names to encoded values

    Returns:
        Dictionary with decoded values
    """
    return {name: decode(value) for name, value in args.items()}


def encode_result(result: Any) -> Dict[str, Any]:
    """
    Encode a function result in SnakeBridge result format.

    Args:
        result: The result value to encode

    Returns:
        Dictionary with success status and encoded result
    """
    return {
        "success": True,
        "result": encode(result)
    }


def encode_error(error: Exception) -> Dict[str, Any]:
    """
    Encode an error in SnakeBridge result format.

    Args:
        error: The exception to encode

    Returns:
        Dictionary with success status and error information
    """
    return {
        "success": False,
        "error": str(error),
        "error_type": type(error).__name__
    }
