"""
pylatexenc helper functions for SnakeBridge.

Provides simple, JSON-safe wrappers for LaTeX parsing and encoding.
"""

import sys
from typing import Any, List

# Add parent directory to path for bridge_base import
sys.path.insert(0, str(__file__).rsplit("/bridges", 1)[0])

from snakebridge_adapter.bridge_base import make_import_guard

# Import guard
_pylatexenc, HAS_PYLATEXENC, _ensure_pylatexenc = make_import_guard("pylatexenc", "pylatexenc")

# Lazy imports for specific submodules
LatexNodes2Text = None
_unicode_to_latex_fn = None
LatexWalker = None
LatexNode = None

if HAS_PYLATEXENC:
    from pylatexenc.latex2text import LatexNodes2Text
    from pylatexenc.latexencode import unicode_to_latex as _unicode_to_latex_fn
    from pylatexenc.latexwalker import LatexWalker, LatexNode


def _node_to_dict(node: Any) -> dict:
    """Convert a LatexNode to a JSON-safe dict."""
    result = {"type": node.__class__.__name__}

    if hasattr(node, "chars"):
        result["chars"] = node.chars

    if hasattr(node, "macroname"):
        result["name"] = node.macroname

    if hasattr(node, "envname"):
        result["env"] = node.envname

    if hasattr(node, "nodelist"):
        result["children"] = _json_safe(node.nodelist)

    if hasattr(node, "nodeargd"):
        nodeargd = node.nodeargd
        if hasattr(nodeargd, "argnlist"):
            result["args"] = _json_safe(nodeargd.argnlist)
        else:
            result["args"] = []

    if hasattr(node, "latex_verbatim"):
        try:
            lv = node.latex_verbatim
            result["latex"] = lv() if callable(lv) else lv
        except Exception:
            pass

    if hasattr(node, "pos"):
        result["pos"] = node.pos

    if hasattr(node, "len"):
        result["len"] = node.len

    return result


def _json_safe(value: Any) -> Any:
    """Convert pylatexenc objects to JSON-safe values."""
    if value is None:
        return None

    if isinstance(value, (str, int, float, bool)):
        return value

    if HAS_PYLATEXENC and LatexNode is not None and isinstance(value, LatexNode):
        return _node_to_dict(value)

    if isinstance(value, (list, tuple)):
        return [_json_safe(v) for v in value]

    if isinstance(value, dict):
        return {str(k): _json_safe(v) for k, v in value.items()}

    return str(value)


# Public API functions

def latex_to_text(latex: str) -> str:
    _ensure_pylatexenc()
    return LatexNodes2Text().latex_to_text(latex)


def unicode_to_latex(text: str) -> str:
    _ensure_pylatexenc()
    return _unicode_to_latex_fn(text)


def parse_latex(latex: str) -> List[dict]:
    _ensure_pylatexenc()
    walker = LatexWalker(latex)
    nodes, _, _ = walker.get_latex_nodes()
    return _json_safe(nodes)
