"""
SymPy helper functions for SnakeBridge.

These wrappers normalize string inputs and return JSON-safe outputs.
"""

import sys
from typing import Any

# Add parent directory to path for bridge_base import
sys.path.insert(0, str(__file__).rsplit("/bridges", 1)[0])

from snakebridge_adapter.bridge_base import make_import_guard, make_json_safe

# Import guard
sp, HAS_SYMPY, _ensure_sympy = make_import_guard("sympy", "sympy")

# JSON-safe serializer for SymPy types
_json_safe = make_json_safe(
    type_check=lambda v: HAS_SYMPY and sp is not None and isinstance(v, sp.Basic),
    convert=str
)


# Input converters (library-specific)

def _to_expr(value: Any):
    _ensure_sympy()
    if isinstance(value, sp.Basic):
        return value
    return sp.sympify(value)


def _to_symbol(value: Any):
    _ensure_sympy()
    if isinstance(value, sp.Symbol):
        return value
    if isinstance(value, (list, tuple)):
        return [sp.Symbol(str(v)) for v in value]
    return sp.Symbol(str(value))


def _to_mapping(mapping: Any):
    _ensure_sympy()
    if mapping is None:
        return {}
    if isinstance(mapping, dict):
        return {_to_symbol(k): _to_expr(v) for k, v in mapping.items()}
    raise ValueError("mapping must be a dict")


# Public API functions

def symbols(names: str):
    _ensure_sympy()
    result = sp.symbols(names)
    if isinstance(result, (tuple, list)):
        return [str(v) for v in result]
    return [str(result)]


def sympify(expr):
    _ensure_sympy()
    return str(sp.sympify(expr))


def eq(lhs, rhs):
    _ensure_sympy()
    return str(sp.Eq(_to_expr(lhs), _to_expr(rhs)))


def solve(expr, symbol=None):
    _ensure_sympy()
    expr_obj = _to_expr(expr)
    if symbol is not None:
        result = sp.solve(expr_obj, _to_symbol(symbol))
    else:
        result = sp.solve(expr_obj)
    return _json_safe(result)


def simplify(expr):
    _ensure_sympy()
    return str(sp.simplify(_to_expr(expr)))


def expand(expr):
    _ensure_sympy()
    return str(sp.expand(_to_expr(expr)))


def factor(expr):
    _ensure_sympy()
    return str(sp.factor(_to_expr(expr)))


def diff(expr, symbol):
    _ensure_sympy()
    return str(sp.diff(_to_expr(expr), _to_symbol(symbol)))


def integrate(expr, symbol):
    _ensure_sympy()
    return str(sp.integrate(_to_expr(expr), _to_symbol(symbol)))


def latex(expr):
    _ensure_sympy()
    return sp.latex(_to_expr(expr))


def n(expr, precision=None):
    _ensure_sympy()
    expr_obj = _to_expr(expr)
    result = sp.N(expr_obj, precision) if precision is not None else sp.N(expr_obj)
    return _json_safe(result)


def subs(expr, mapping):
    _ensure_sympy()
    return str(_to_expr(expr).subs(_to_mapping(mapping)))


def free_symbols(expr):
    _ensure_sympy()
    return [str(s) for s in _to_expr(expr).free_symbols]


def sqrt(expr):
    _ensure_sympy()
    return str(sp.sqrt(_to_expr(expr)))


def sin(expr):
    _ensure_sympy()
    return str(sp.sin(_to_expr(expr)))


def cos(expr):
    _ensure_sympy()
    return str(sp.cos(_to_expr(expr)))


def tan(expr):
    _ensure_sympy()
    return str(sp.tan(_to_expr(expr)))


def log(expr):
    _ensure_sympy()
    return str(sp.log(_to_expr(expr)))


def exp(expr):
    _ensure_sympy()
    return str(sp.exp(_to_expr(expr)))
