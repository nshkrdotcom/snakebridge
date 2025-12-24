"""
Generic JSON-safe serializer for SnakeBridge adapter.

Converts Python values to JSON-serializable types.
Library-specific serialization is handled by individual bridges.
"""

from typing import Any


def json_safe(value: Any) -> Any:
    """Convert a Python value to a JSON-safe representation.

    Handles generic Python types only. Library-specific types
    (SymPy, NumPy, pylatexenc, etc.) must be serialized by their
    respective bridges before calling this function.
    """
    if value is None:
        return None

    if isinstance(value, (str, int, float, bool)):
        return value

    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")

    if isinstance(value, complex):
        return {"real": value.real, "imag": value.imag}

    if isinstance(value, (list, tuple)):
        return [json_safe(v) for v in value]

    if isinstance(value, set):
        return [json_safe(v) for v in value]

    if isinstance(value, dict):
        return {str(k): json_safe(v) for k, v in value.items()}

    # Fallback: convert to string
    return str(value)
