"""
ProofPipeline parsing helpers.

Provides a SymPy parser configured to accept implicit multiplication
so inputs like "2x" parse successfully.
"""

from sympy.parsing.sympy_parser import (
    parse_expr,
    standard_transformations,
    implicit_multiplication_application,
)


def parse_expr_implicit(expr: str):
    transformations = standard_transformations + (implicit_multiplication_application,)
    return parse_expr(expr, transformations=transformations)

