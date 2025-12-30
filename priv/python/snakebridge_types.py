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
"""

import base64
import inspect
import json
import math
import os
from datetime import datetime, date, time
from typing import Any, Dict, List, Union

SCHEMA_VERSION = 1


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

    # Handle basic JSON-safe types
    if isinstance(value, (bool, int, str)):
        return value

    # Handle float (check for special values)
    if isinstance(value, float):
        if math.isinf(value):
            if value > 0:
                return _tag("special_float", {"value": "infinity"})
            else:
                return _tag("special_float", {"value": "neg_infinity"})
        elif math.isnan(value):
            return _tag("special_float", {"value": "nan"})
        else:
            return value

    # Handle tagged atoms
    if isinstance(value, Atom):
        return _tag("atom", {"value": value.value})

    # Handle tuple
    if isinstance(value, tuple):
        return _tag("tuple", {"elements": [encode(item) for item in value]})

    # Handle set
    if isinstance(value, set):
        return _tag(
            "set",
            {
                "elements": [
                    encode(item) for item in sorted(value, key=lambda x: (type(x).__name__, str(x)))
                ]
            },
        )

    # Handle frozenset
    if isinstance(value, frozenset):
        return _tag(
            "frozenset",
            {
                "elements": [
                    encode(item) for item in sorted(value, key=lambda x: (type(x).__name__, str(x)))
                ]
            },
        )

    # Handle bytes
    if isinstance(value, bytes):
        return _tag("bytes", {"data": base64.b64encode(value).decode("ascii")})

    # Handle bytearray
    if isinstance(value, bytearray):
        return _tag("bytes", {"data": base64.b64encode(bytes(value)).decode("ascii")})

    # Handle complex
    if isinstance(value, complex):
        return _tag("complex", {"real": value.real, "imag": value.imag})

    # Handle datetime
    if isinstance(value, datetime):
        return _tag("datetime", {"value": value.isoformat()})

    # Handle date
    if isinstance(value, date):
        return _tag("date", {"value": value.isoformat()})

    # Handle time
    if isinstance(value, time):
        return _tag("time", {"value": value.isoformat()})

    # Handle list
    if isinstance(value, list):
        return [encode(item) for item in value]

    # Handle dict
    if isinstance(value, dict):
        return {encode_dict_key(k): encode(v) for k, v in value.items()}

    # Detect generators and iterators
    if inspect.isgenerator(value):
        return {"__needs_stream_ref__": True, "__stream_type__": "generator"}

    if hasattr(value, "__iter__") and hasattr(value, "__next__") and not isinstance(
        value, (str, bytes, bytearray, list, tuple, dict, set)
    ):
        # Prefer regular refs for context managers (e.g. file objects).
        if hasattr(value, "__enter__") and hasattr(value, "__exit__"):
            pass
        else:
            return {"__needs_stream_ref__": True, "__stream_type__": "iterator"}

    # For any other type, create auto-ref if in adapter context
    # This is handled by encode_result() in snakebridge_adapter.py
    # which wraps with context. Here we provide fallback.
    try:
        # Check if this is a complex object that should be a ref
        if hasattr(value, "__class__") and not isinstance(
            value, (str, bytes, int, float, bool, type(None), list, dict, tuple, set)
        ):
            # Signal that this needs ref wrapping
            return {
                "__needs_ref__": True,
                "__type_name__": type(value).__name__,
                "__module__": type(value).__module__,
            }
        return str(value)
    except Exception:
        return f"<non-serializable: {type(value).__name__}>"


def encode_dict_key(key: Any) -> str:
    """
    Encode a dictionary key to a string.

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

            else:
                # Unknown type tag, return as-is
                return {k: decode(v, session_id=session_id, context=context) for k, v in value.items()}
        else:
            # Regular dict, decode recursively
            return {k: decode(v, session_id=session_id, context=context) for k, v in value.items()}

    # Return as-is for any other type
    return value


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
