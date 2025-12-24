"""
Base utilities for SnakeBridge library bridges.

Provides common patterns to reduce boilerplate in per-library bridges:
- Import guards for optional dependencies
- JSON-safe serializers with library-specific type hooks
- Array/tensor serializers for ML/scientific libraries
"""

from typing import Any, Callable, List, Optional, Tuple, Type


def make_import_guard(
    module_name: str,
    pip_package: str
) -> Tuple[Any, bool, Callable[[], None]]:
    """
    Create an import guard for an optional library dependency.

    Returns:
        Tuple of (module, has_module, ensure_fn)

    Example:
        sp, HAS_SYMPY, ensure_sympy = make_import_guard("sympy", "sympy")

        def simplify(expr):
            ensure_sympy()
            return str(sp.simplify(expr))
    """
    try:
        module = __import__(module_name)
        has_module = True
    except ImportError:
        module = None
        has_module = False

    def ensure() -> None:
        if not has_module:
            raise ImportError(
                f"{module_name} not installed. Install with: pip install {pip_package}"
            )

    return module, has_module, ensure


def make_json_safe(
    type_check: Optional[Callable[[Any], bool]] = None,
    convert: Callable[[Any], Any] = str
) -> Callable[[Any], Any]:
    """
    Create a recursive JSON-safe serializer with an optional library-specific type hook.

    Args:
        type_check: Function returning True if value is a library-specific type
        convert: Function to convert library types to JSON-safe values

    Example:
        _json_safe = make_json_safe(
            type_check=lambda v: HAS_SYMPY and isinstance(v, sp.Basic),
            convert=str
        )
    """
    def json_safe(value: Any) -> Any:
        if value is None:
            return None

        if isinstance(value, (str, int, float, bool)):
            return value

        if type_check is not None and type_check(value):
            return convert(value)

        if isinstance(value, (list, tuple)):
            return [json_safe(v) for v in value]

        if isinstance(value, dict):
            return {str(k): json_safe(v) for k, v in value.items()}

        return str(value)

    return json_safe


def make_array_serializer(
    array_types: List[Type],
    scalar_types: Optional[List[Type]] = None,
    data_method: str = "tolist",
    shape_attr: str = "shape",
    dtype_attr: str = "dtype",
) -> Callable[[Any], Any]:
    """
    Create a serializer for array/tensor types (numpy, torch, jax, etc.).

    Handles both array types (converted to {data, shape, dtype}) and
    scalar types (unwrapped via .item()).

    Args:
        array_types: List of array types to handle (e.g., [np.ndarray])
        scalar_types: List of scalar types to unwrap (e.g., [np.generic])
        data_method: Method name to get list data (default: "tolist")
        shape_attr: Attribute name for shape (default: "shape")
        dtype_attr: Attribute name for dtype (default: "dtype")

    Example:
        _json_safe = make_array_serializer(
            array_types=[np.ndarray],
            scalar_types=[np.generic],
        )
    """
    scalar_types = scalar_types or []

    def array_to_dict(arr: Any) -> dict:
        data_fn = getattr(arr, data_method)
        return {
            "data": json_safe(data_fn()),
            "shape": list(getattr(arr, shape_attr)),
            "dtype": str(getattr(arr, dtype_attr)),
        }

    def json_safe(value: Any) -> Any:
        if value is None:
            return None

        if isinstance(value, (str, int, float, bool)):
            return value

        # Check array types
        for arr_type in array_types:
            if arr_type is not None and isinstance(value, arr_type):
                return array_to_dict(value)

        # Check scalar types (unwrap via .item())
        for scalar_type in scalar_types:
            if scalar_type is not None and isinstance(value, scalar_type):
                return json_safe(value.item())

        if isinstance(value, (list, tuple)):
            return [json_safe(v) for v in value]

        if isinstance(value, dict):
            return {str(k): json_safe(v) for k, v in value.items()}

        return str(value)

    return json_safe
