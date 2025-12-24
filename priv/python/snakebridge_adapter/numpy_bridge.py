"""
NumPy helper functions for SnakeBridge.

Provides JSON-safe wrappers for core array operations.
"""

from typing import Any, List, Optional

from . import serializer

try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    np = None
    HAS_NUMPY = False


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


def _ensure_numpy() -> None:
    if not HAS_NUMPY:
        raise ImportError("numpy not installed. Install with: pip install numpy")


def _to_numpy_array(data: Any, dtype: Optional[str] = None) -> "np.ndarray":
    _ensure_numpy()
    arr = data if isinstance(data, np.ndarray) else np.array(data)

    if dtype and dtype in SUPPORTED_DTYPES:
        arr = arr.astype(SUPPORTED_DTYPES[dtype])

    return arr


def _array_response(arr: "np.ndarray") -> dict:
    return {
        "data": serializer.json_safe(arr.tolist()),
        "shape": list(arr.shape),
        "dtype": str(arr.dtype)
    }


def array(data: list, dtype: Optional[str] = None, shape: Optional[List[int]] = None) -> dict:
    _ensure_numpy()
    arr = _to_numpy_array(data, dtype)

    if shape:
        arr = arr.reshape(shape)

    return _array_response(arr)


def zeros(shape: List[int], dtype: str = "float64") -> dict:
    _ensure_numpy()
    np_dtype = SUPPORTED_DTYPES.get(dtype, "float64")
    arr = np.zeros(shape, dtype=np_dtype)
    return _array_response(arr)


def ones(shape: List[int], dtype: str = "float64") -> dict:
    _ensure_numpy()
    np_dtype = SUPPORTED_DTYPES.get(dtype, "float64")
    arr = np.ones(shape, dtype=np_dtype)
    return _array_response(arr)


def arange(start: float, stop: Optional[float] = None, step: float = 1, dtype: Optional[str] = None) -> dict:
    _ensure_numpy()
    np_dtype = SUPPORTED_DTYPES.get(dtype, None)
    arr = np.arange(start, stop, step, dtype=np_dtype)
    return _array_response(arr)


def linspace(start: float, stop: float, num: int = 50, dtype: Optional[str] = None) -> dict:
    _ensure_numpy()
    np_dtype = SUPPORTED_DTYPES.get(dtype, None)
    arr = np.linspace(start, stop, num, dtype=np_dtype)
    return _array_response(arr)


def mean(data: list, axis: Optional[int] = None) -> dict:
    _ensure_numpy()
    arr = _to_numpy_array(data)
    result = np.mean(arr, axis=axis)
    return _wrap_result(result)


def sum(data: list, axis: Optional[int] = None) -> dict:
    _ensure_numpy()
    arr = _to_numpy_array(data)
    result = np.sum(arr, axis=axis)
    return _wrap_result(result)


def dot(a: list, b: list) -> dict:
    _ensure_numpy()
    arr_a = _to_numpy_array(a)
    arr_b = _to_numpy_array(b)
    result = np.dot(arr_a, arr_b)
    return _wrap_result(result)


def reshape(data: list, shape: List[int]) -> dict:
    _ensure_numpy()
    arr = _to_numpy_array(data)
    reshaped = arr.reshape(shape)
    return _array_response(reshaped)


def transpose(data: list, axes: Optional[List[int]] = None) -> dict:
    _ensure_numpy()
    arr = _to_numpy_array(data)
    result = np.transpose(arr, axes=axes)
    return _array_response(result)


def _wrap_result(result: Any) -> dict:
    if HAS_NUMPY and isinstance(result, np.ndarray):
        return _array_response(result)

    return {"result": serializer.json_safe(result)}
