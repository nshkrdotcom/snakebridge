"""
SnakeBridge Type Encoding System

Provides encoding and decoding functions for converting between Python and Elixir types.
Uses tagged JSON format with __type__ markers for special types that don't map directly to JSON.

Supported special types:
- tuple: Python tuples (encoded as lists with __type__ tag)
- set: Python sets (encoded as lists with __type__ tag)
- frozenset: Python frozensets (encoded as lists with __type__ tag)
- bytes: Python bytes (encoded as base64 strings with __type__ tag)
- complex: Python complex numbers (encoded as [real, imag] with __type__ tag)
- datetime: datetime objects (encoded as ISO 8601 strings with __type__ tag)
- date: date objects (encoded as ISO 8601 strings with __type__ tag)
- time: time objects (encoded as ISO 8601 strings with __type__ tag)
- infinity: Positive infinity (encoded with __type__ tag)
- neg_infinity: Negative infinity (encoded with __type__ tag)
- nan: Not a Number (encoded with __type__ tag)
"""

import base64
import math
from datetime import datetime, date, time
from typing import Any, Dict, List, Union


def encode(value: Any) -> Any:
    """
    Encode a Python value to a JSON-safe value with __type__ tags for special types.

    Args:
        value: The Python value to encode

    Returns:
        A JSON-safe value (possibly with __type__ tags)

    Examples:
        >>> encode((1, 2, 3))
        {'__type__': 'tuple', 'value': [1, 2, 3]}

        >>> encode({1, 2, 3})
        {'__type__': 'set', 'value': [1, 2, 3]}

        >>> encode(b'hello')
        {'__type__': 'bytes', 'value': 'aGVsbG8='}

        >>> encode(1+2j)
        {'__type__': 'complex', 'real': 1.0, 'imag': 2.0}
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
                return {"__type__": "infinity"}
            else:
                return {"__type__": "neg_infinity"}
        elif math.isnan(value):
            return {"__type__": "nan"}
        else:
            return value

    # Handle tuple
    if isinstance(value, tuple):
        return {
            "__type__": "tuple",
            "value": [encode(item) for item in value]
        }

    # Handle set
    if isinstance(value, set):
        return {
            "__type__": "set",
            "value": [encode(item) for item in sorted(value, key=lambda x: (type(x).__name__, x))]
        }

    # Handle frozenset
    if isinstance(value, frozenset):
        return {
            "__type__": "frozenset",
            "value": [encode(item) for item in sorted(value, key=lambda x: (type(x).__name__, x))]
        }

    # Handle bytes
    if isinstance(value, bytes):
        return {
            "__type__": "bytes",
            "value": base64.b64encode(value).decode('ascii')
        }

    # Handle bytearray
    if isinstance(value, bytearray):
        return {
            "__type__": "bytes",
            "value": base64.b64encode(bytes(value)).decode('ascii')
        }

    # Handle complex
    if isinstance(value, complex):
        return {
            "__type__": "complex",
            "real": value.real,
            "imag": value.imag
        }

    # Handle datetime
    if isinstance(value, datetime):
        return {
            "__type__": "datetime",
            "value": value.isoformat()
        }

    # Handle date
    if isinstance(value, date):
        return {
            "__type__": "date",
            "value": value.isoformat()
        }

    # Handle time
    if isinstance(value, time):
        return {
            "__type__": "time",
            "value": value.isoformat()
        }

    # Handle list
    if isinstance(value, list):
        return [encode(item) for item in value]

    # Handle dict
    if isinstance(value, dict):
        return {encode_dict_key(k): encode(v) for k, v in value.items()}

    # For any other type, try to convert to string
    try:
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


def decode(value: Any) -> Any:
    """
    Decode a JSON value with __type__ tags back to Python values.

    Args:
        value: The JSON value to decode (possibly with __type__ tags)

    Returns:
        The decoded Python value

    Examples:
        >>> decode({'__type__': 'tuple', 'value': [1, 2, 3]})
        (1, 2, 3)

        >>> decode({'__type__': 'set', 'value': [1, 2, 3]})
        {1, 2, 3}

        >>> decode({'__type__': 'bytes', 'value': 'aGVsbG8='})
        b'hello'

        >>> decode({'__type__': 'complex', 'real': 1.0, 'imag': 2.0})
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
        return [decode(item) for item in value]

    # Handle dict (check for __type__ tag)
    if isinstance(value, dict):
        if "__type__" in value:
            type_tag = value["__type__"]

            if type_tag == "tuple":
                return tuple(decode(item) for item in value["value"])

            elif type_tag == "set":
                return set(decode(item) for item in value["value"])

            elif type_tag == "frozenset":
                return frozenset(decode(item) for item in value["value"])

            elif type_tag == "bytes":
                return base64.b64decode(value["value"])

            elif type_tag == "complex":
                return complex(value["real"], value["imag"])

            elif type_tag == "datetime":
                return datetime.fromisoformat(value["value"])

            elif type_tag == "date":
                return date.fromisoformat(value["value"])

            elif type_tag == "time":
                return time.fromisoformat(value["value"])

            elif type_tag == "infinity":
                return float('inf')

            elif type_tag == "neg_infinity":
                return float('-inf')

            elif type_tag == "nan":
                return float('nan')

            else:
                # Unknown type tag, return as-is
                return {k: decode(v) for k, v in value.items()}
        else:
            # Regular dict, decode recursively
            return {k: decode(v) for k, v in value.items()}

    # Return as-is for any other type
    return value


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
