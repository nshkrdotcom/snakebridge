"""
NumPy helper functions for SnakeBridge.

Provides JSON-safe wrappers for core array operations.
"""

import sys
from typing import Any, List, Optional

# Add parent directory to path for bridge_base import
sys.path.insert(0, str(__file__).rsplit("/bridges", 1)[0])

from snakebridge_adapter.bridge_base import make_import_guard, make_array_serializer

# Import guard
np, HAS_NUMPY, _ensure_numpy = make_import_guard("numpy", "numpy")

# JSON-safe serializer for NumPy types
if HAS_NUMPY:
    _json_safe = make_array_serializer(
        array_types=[np.ndarray],
        scalar_types=[np.generic],
    )
else:
    # Fallback when numpy not installed
    def _json_safe(value: Any) -> Any:
        if value is None:
            return None
        if isinstance(value, (str, int, float, bool)):
            return value
        if isinstance(value, (list, tuple)):
            return [_json_safe(v) for v in value]
        if isinstance(value, dict):
            return {str(k): _json_safe(v) for k, v in value.items()}
        return str(value)


SUPPORTED_DTYPES = {
    "float32": "float32",
    "float64": "float64",
    "int8": "int8",
    "int16": "int16",
    "int32": "int32",
    "int64": "int64",
    "uint8": "uint8",
    "uint16": "uint16",
    "uint32": "uint32",
    "uint64": "uint64",
    "bool": "bool",
    "complex64": "complex64",
    "complex128": "complex128",
}


def _to_array(data: Any, dtype: Optional[str] = None) -> "np.ndarray":
    """Convert data to numpy array with optional dtype."""
    _ensure_numpy()
    arr = data if isinstance(data, np.ndarray) else np.array(data)
    if dtype and dtype in SUPPORTED_DTYPES:
        arr = arr.astype(SUPPORTED_DTYPES[dtype])
    return arr


def _array_response(arr: "np.ndarray") -> dict:
    """Convert array to response dict."""
    return {
        "data": _json_safe(arr.tolist()),
        "shape": list(arr.shape),
        "dtype": str(arr.dtype),
    }


def _wrap_result(result: Any) -> dict:
    """Wrap result, converting arrays to response format."""
    if HAS_NUMPY and isinstance(result, np.ndarray):
        return _array_response(result)
    return {"result": _json_safe(result)}


# Public API functions

def array(data: list, dtype: Optional[str] = None, shape: Optional[List[int]] = None) -> dict:
    _ensure_numpy()
    arr = _to_array(data, dtype)
    if shape:
        arr = arr.reshape(shape)
    return _array_response(arr)


def zeros(shape: List[int], dtype: str = "float64") -> dict:
    _ensure_numpy()
    arr = np.zeros(shape, dtype=SUPPORTED_DTYPES.get(dtype, "float64"))
    return _array_response(arr)


def ones(shape: List[int], dtype: str = "float64") -> dict:
    _ensure_numpy()
    arr = np.ones(shape, dtype=SUPPORTED_DTYPES.get(dtype, "float64"))
    return _array_response(arr)


def arange(start: float, stop: Optional[float] = None, step: float = 1, dtype: Optional[str] = None) -> dict:
    _ensure_numpy()
    arr = np.arange(start, stop, step, dtype=SUPPORTED_DTYPES.get(dtype))
    return _array_response(arr)


def linspace(start: float, stop: float, num: int = 50, dtype: Optional[str] = None) -> dict:
    _ensure_numpy()
    arr = np.linspace(start, stop, num, dtype=SUPPORTED_DTYPES.get(dtype))
    return _array_response(arr)


def mean(data: list, axis: Optional[int] = None) -> dict:
    _ensure_numpy()
    result = np.mean(_to_array(data), axis=axis)
    return _wrap_result(result)


def sum(data: list, axis: Optional[int] = None) -> dict:
    _ensure_numpy()
    result = np.sum(_to_array(data), axis=axis)
    return _wrap_result(result)


def dot(a: list, b: list) -> dict:
    _ensure_numpy()
    result = np.dot(_to_array(a), _to_array(b))
    return _wrap_result(result)


def reshape(data: list, shape: List[int]) -> dict:
    _ensure_numpy()
    arr = _to_array(data).reshape(shape)
    return _array_response(arr)


def transpose(data: list, axes: Optional[List[int]] = None) -> dict:
    _ensure_numpy()
    arr = np.transpose(_to_array(data), axes=axes)
    return _array_response(arr)
