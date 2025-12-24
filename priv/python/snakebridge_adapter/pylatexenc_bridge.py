"""
pylatexenc helper functions for SnakeBridge.

Provides simple, JSON-safe wrappers for LaTeX parsing and encoding.
"""

from typing import List

from . import serializer

try:
    from pylatexenc.latex2text import LatexNodes2Text
    from pylatexenc.latexencode import unicode_to_latex as _unicode_to_latex
    from pylatexenc.latexwalker import LatexWalker
    HAS_PYLATEXENC = True
except ImportError:
    LatexNodes2Text = None
    _unicode_to_latex = None
    LatexWalker = None
    HAS_PYLATEXENC = False


def _ensure_pylatexenc():
    if not HAS_PYLATEXENC:
        raise ImportError("pylatexenc not installed. Install with: pip install pylatexenc")


def latex_to_text(latex: str) -> str:
    _ensure_pylatexenc()
    return LatexNodes2Text().latex_to_text(latex)


def unicode_to_latex(text: str) -> str:
    _ensure_pylatexenc()
    return _unicode_to_latex(text)


def parse_latex(latex: str) -> List[dict]:
    _ensure_pylatexenc()
    walker = LatexWalker(latex)
    nodes, _, _ = walker.get_latex_nodes()
    return serializer.json_safe(nodes)
