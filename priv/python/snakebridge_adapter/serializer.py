"""
Shared JSON-safe serializer for SnakeBridge adapter and wrappers.
"""

from typing import Any

try:
    import sympy
    HAS_SYMPY = True
except ImportError:
    sympy = None
    HAS_SYMPY = False

try:
    from pylatexenc.latexwalker import LatexNode
    HAS_PYLATEXENC = True
except ImportError:
    LatexNode = None
    HAS_PYLATEXENC = False

try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    np = None
    HAS_NUMPY = False


def json_safe(value: Any) -> Any:
    if value is None:
        return None

    if isinstance(value, (str, int, float, bool)):
        return value

    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")

    if isinstance(value, complex):
        return {"real": value.real, "imag": value.imag}

    if HAS_NUMPY:
        if isinstance(value, np.ndarray):
            return _numpy_array_to_dict(value)
        if isinstance(value, np.generic):
            return json_safe(value.item())

    if isinstance(value, (list, tuple, set)):
        return [json_safe(v) for v in value]

    if isinstance(value, dict):
        return {str(k): json_safe(v) for k, v in value.items()}

    if HAS_SYMPY and isinstance(value, sympy.Basic):
        return str(value)

    if HAS_PYLATEXENC and LatexNode is not None and isinstance(value, LatexNode):
        return _pylatexenc_node_to_dict(value)

    if hasattr(value, "__dict__"):
        try:
            return json_safe(value.__dict__)
        except Exception:
            pass

    return str(value)


def _numpy_array_to_dict(arr: "np.ndarray") -> dict:
    return {
        "data": json_safe(arr.tolist()),
        "shape": list(arr.shape),
        "dtype": str(arr.dtype)
    }


def _pylatexenc_node_to_dict(node: Any) -> dict:
    result = {"type": node.__class__.__name__}

    if hasattr(node, "chars"):
        result["chars"] = node.chars

    if hasattr(node, "macroname"):
        result["name"] = node.macroname

    if hasattr(node, "envname"):
        result["env"] = node.envname

    if hasattr(node, "nodelist"):
        result["children"] = json_safe(node.nodelist)

    if hasattr(node, "nodeargd"):
        nodeargd = node.nodeargd
        args = []

        if hasattr(nodeargd, "argnlist"):
            args = json_safe(nodeargd.argnlist)

        result["args"] = args

    if hasattr(node, "latex_verbatim"):
        try:
            latex_value = node.latex_verbatim() if callable(node.latex_verbatim) else node.latex_verbatim
            result["latex"] = latex_value
        except Exception:
            pass

    if hasattr(node, "pos"):
        result["pos"] = node.pos

    if hasattr(node, "len"):
        result["len"] = node.len

    return result
