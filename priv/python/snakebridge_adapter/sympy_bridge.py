"""
SymPy helper functions for SnakeBridge.

These wrappers normalize string inputs and return JSON-safe outputs.
"""

from typing import Any

from . import serializer

try:
    import sympy as sp
    HAS_SYMPY = True
except ImportError:
    sp = None
    HAS_SYMPY = False


def _ensure_sympy():
    if not HAS_SYMPY:
        raise ImportError("sympy not installed. Install with: pip install sympy")


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
        converted = {}
        for key, val in mapping.items():
            converted[_to_symbol(key)] = _to_expr(val)
        return converted
    raise ValueError("mapping must be a dict")


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
        symbol_obj = _to_symbol(symbol)
        result = sp.solve(expr_obj, symbol_obj)
    else:
        result = sp.solve(expr_obj)
    return serializer.json_safe(result)


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
    return serializer.json_safe(result)


def subs(expr, mapping):
    _ensure_sympy()
    expr_obj = _to_expr(expr)
    mapping_obj = _to_mapping(mapping)
    return str(expr_obj.subs(mapping_obj))


def free_symbols(expr):
    _ensure_sympy()
    expr_obj = _to_expr(expr)
    return [str(s) for s in expr_obj.free_symbols]


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
