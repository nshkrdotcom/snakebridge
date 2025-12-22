"""
NumPy Adapter for SnakeBridge - Array Operations with JSON Serialization

Specialized adapter for NumPy providing:
- Array creation and manipulation
- JSON-serializable array responses (as lists)
- dtype preservation and conversion
- Basic linear algebra operations

Install: pip install numpy
No API keys required.

Phase 1: JSON serialization (current)
Phase 2: Benchmark vs MessagePack (planned)
Phase 3: Arrow IPC (future, v1.5+)
"""

import logging
import traceback
from typing import Any, Dict, List, Optional, Union

# Import base adapter
from snakebridge_adapter.adapter import SnakeBridgeAdapter

try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False
    np = None

try:
    from snakepit_bridge.base_adapter_threaded import tool
except ImportError:
    def tool(description="", **kwargs):
        def decorator(func):
            return func
        return decorator

logger = logging.getLogger(__name__)


class NumpyAdapter(SnakeBridgeAdapter):
    """
    Specialized adapter for NumPy array operations.

    Inherits from SnakeBridgeAdapter for describe_library and call_python,
    and adds specialized tools for efficient array operations.

    All array results are serialized as JSON-compatible lists with metadata.

    Response format for arrays:
    {
        "success": True,
        "data": [[1, 2, 3], [4, 5, 6]],  # nested lists
        "shape": [2, 3],
        "dtype": "float64"
    }
    """

    # Supported dtypes with their numpy types
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

    def __init__(self, ttl_seconds: int = 3600, max_instances: int = 1000):
        """Initialize NumPy adapter."""
        super().__init__(ttl_seconds=ttl_seconds, max_instances=max_instances)
        self._check_numpy()
        logger.info("NumpyAdapter initialized")

    def _check_numpy(self):
        """Verify NumPy is available."""
        if not HAS_NUMPY:
            logger.warning("NumPy not installed. Install with: pip install numpy")

    def _json_safe(self, value):
        """Convert values to JSON-serializable equivalents."""
        if isinstance(value, complex):
            return {"real": value.real, "imag": value.imag}

        if isinstance(value, list):
            return [self._json_safe(v) for v in value]

        if isinstance(value, tuple):
            return [self._json_safe(v) for v in value]

        return value

    def execute_tool(self, tool_name: str, arguments: dict, context):
        """
        Dispatch tool calls.

        NumPy-specific tools are handled here, all others fall through
        to the parent SnakeBridgeAdapter.
        """
        logger.debug(f"NumpyAdapter.execute_tool: {tool_name}")

        # Check NumPy availability
        if not HAS_NUMPY:
            return {
                "success": False,
                "error": "NumPy not installed. Install with: pip install numpy"
            }

        # NumPy-specific tools
        if tool_name == "np_create_array":
            return self.create_array(
                data=arguments.get("data"),
                dtype=arguments.get("dtype"),
                shape=arguments.get("shape")
            )
        elif tool_name == "np_zeros":
            return self.create_zeros(
                shape=arguments.get("shape"),
                dtype=arguments.get("dtype", "float64")
            )
        elif tool_name == "np_ones":
            return self.create_ones(
                shape=arguments.get("shape"),
                dtype=arguments.get("dtype", "float64")
            )
        elif tool_name == "np_arange":
            return self.create_arange(
                start=arguments.get("start", 0),
                stop=arguments.get("stop"),
                step=arguments.get("step", 1),
                dtype=arguments.get("dtype")
            )
        elif tool_name == "np_linspace":
            return self.create_linspace(
                start=arguments.get("start"),
                stop=arguments.get("stop"),
                num=arguments.get("num", 50),
                dtype=arguments.get("dtype")
            )
        elif tool_name == "np_mean":
            return self.compute_mean(
                data=arguments.get("data"),
                axis=arguments.get("axis")
            )
        elif tool_name == "np_sum":
            return self.compute_sum(
                data=arguments.get("data"),
                axis=arguments.get("axis")
            )
        elif tool_name == "np_dot":
            return self.compute_dot(
                a=arguments.get("a"),
                b=arguments.get("b")
            )
        elif tool_name == "np_reshape":
            return self.reshape_array(
                data=arguments.get("data"),
                shape=arguments.get("shape")
            )
        elif tool_name == "np_transpose":
            return self.transpose_array(
                data=arguments.get("data"),
                axes=arguments.get("axes")
            )

        # Fall through to parent for generic operations
        return super().execute_tool(tool_name, arguments, context)

    def _array_to_response(self, arr: "np.ndarray") -> dict:
        """Convert NumPy array to JSON-serializable response."""
        return {
            "success": True,
            "data": self._json_safe(arr.tolist()),
            "shape": list(arr.shape),
            "dtype": str(arr.dtype)
        }

    def _to_numpy_array(self, data: Union[list, "np.ndarray"], dtype: Optional[str] = None) -> "np.ndarray":
        """Convert input data to NumPy array."""
        if isinstance(data, np.ndarray):
            arr = data
        else:
            arr = np.array(data)

        if dtype and dtype in self.SUPPORTED_DTYPES:
            arr = arr.astype(self.SUPPORTED_DTYPES[dtype])

        return arr

    @tool(description="Create NumPy array from data")
    def create_array(
        self,
        data: list,
        dtype: Optional[str] = None,
        shape: Optional[List[int]] = None
    ) -> dict:
        """
        Create a NumPy array from input data.

        Args:
            data: Nested list of values
            dtype: Data type (float32, float64, int32, int64, etc.)
            shape: Optional shape to reshape to

        Returns:
            Array response with data, shape, and dtype
        """
        try:
            arr = self._to_numpy_array(data, dtype)

            if shape:
                arr = arr.reshape(shape)

            return self._array_to_response(arr)

        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "traceback": traceback.format_exc()
            }

    @tool(description="Create array of zeros")
    def create_zeros(self, shape: List[int], dtype: str = "float64") -> dict:
        """Create array filled with zeros."""
        try:
            np_dtype = self.SUPPORTED_DTYPES.get(dtype, "float64")
            arr = np.zeros(shape, dtype=np_dtype)
            return self._array_to_response(arr)

        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "traceback": traceback.format_exc()
            }

    @tool(description="Create array of ones")
    def create_ones(self, shape: List[int], dtype: str = "float64") -> dict:
        """Create array filled with ones."""
        try:
            np_dtype = self.SUPPORTED_DTYPES.get(dtype, "float64")
            arr = np.ones(shape, dtype=np_dtype)
            return self._array_to_response(arr)

        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "traceback": traceback.format_exc()
            }

    @tool(description="Create evenly spaced values within interval")
    def create_arange(
        self,
        start: float = 0,
        stop: Optional[float] = None,
        step: float = 1,
        dtype: Optional[str] = None
    ) -> dict:
        """Create array with evenly spaced values."""
        try:
            if stop is None:
                # numpy.arange(stop) syntax
                arr = np.arange(start)
            else:
                arr = np.arange(start, stop, step)

            if dtype and dtype in self.SUPPORTED_DTYPES:
                arr = arr.astype(self.SUPPORTED_DTYPES[dtype])

            return self._array_to_response(arr)

        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "traceback": traceback.format_exc()
            }

    @tool(description="Create evenly spaced numbers over interval")
    def create_linspace(
        self,
        start: float,
        stop: float,
        num: int = 50,
        dtype: Optional[str] = None
    ) -> dict:
        """Create array of evenly spaced numbers."""
        try:
            arr = np.linspace(start, stop, num)

            if dtype and dtype in self.SUPPORTED_DTYPES:
                arr = arr.astype(self.SUPPORTED_DTYPES[dtype])

            return self._array_to_response(arr)

        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "traceback": traceback.format_exc()
            }

    @tool(description="Compute arithmetic mean")
    def compute_mean(self, data: list, axis: Optional[int] = None) -> dict:
        """Compute the arithmetic mean."""
        try:
            arr = self._to_numpy_array(data)
            result = np.mean(arr, axis=axis)

            if isinstance(result, np.ndarray):
                return self._array_to_response(result)
            else:
                return {
                    "success": True,
                    "result": float(result)
                }

        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "traceback": traceback.format_exc()
            }

    @tool(description="Compute sum of elements")
    def compute_sum(self, data: list, axis: Optional[int] = None) -> dict:
        """Compute the sum of array elements."""
        try:
            arr = self._to_numpy_array(data)
            result = np.sum(arr, axis=axis)

            if isinstance(result, np.ndarray):
                return self._array_to_response(result)
            else:
                return {
                    "success": True,
                    "result": float(result)
                }

        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "traceback": traceback.format_exc()
            }

    @tool(description="Compute dot product")
    def compute_dot(self, a: list, b: list) -> dict:
        """Compute the dot product of two arrays."""
        try:
            arr_a = self._to_numpy_array(a)
            arr_b = self._to_numpy_array(b)
            result = np.dot(arr_a, arr_b)

            if isinstance(result, np.ndarray):
                return self._array_to_response(result)
            else:
                return {
                    "success": True,
                    "result": float(result)
                }

        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "traceback": traceback.format_exc()
            }

    @tool(description="Reshape array")
    def reshape_array(self, data: list, shape: List[int]) -> dict:
        """Reshape an array to a new shape."""
        try:
            arr = self._to_numpy_array(data)
            result = arr.reshape(shape)
            return self._array_to_response(result)

        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "traceback": traceback.format_exc()
            }

    @tool(description="Transpose array")
    def transpose_array(self, data: list, axes: Optional[List[int]] = None) -> dict:
        """Transpose an array."""
        try:
            arr = self._to_numpy_array(data)
            if axes:
                result = np.transpose(arr, axes)
            else:
                result = np.transpose(arr)
            return self._array_to_response(result)

        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "traceback": traceback.format_exc()
            }
