"""
math-verify helper functions for SnakeBridge.

Thin wrappers that normalize the most common API entry points.
"""

from typing import Any

try:
    import math_verify
    HAS_MATH_VERIFY = True
except ImportError:
    math_verify = None
    HAS_MATH_VERIFY = False


def _ensure_math_verify():
    if not HAS_MATH_VERIFY:
        raise ImportError("math-verify not installed. Install with: pip install math-verify")


def parse(text: str, **kwargs) -> Any:
    _ensure_math_verify()
    if hasattr(math_verify, "parse"):
        return math_verify.parse(text, **kwargs)
    if hasattr(math_verify, "parser") and hasattr(math_verify.parser, "parse"):
        return math_verify.parser.parse(text, **kwargs)
    raise AttributeError("math_verify.parse not found")


def verify(gold: Any, answer: Any, **kwargs) -> Any:
    _ensure_math_verify()
    if hasattr(math_verify, "verify"):
        return math_verify.verify(gold, answer, **kwargs)
    if hasattr(math_verify, "verifier") and hasattr(math_verify.verifier, "verify"):
        return math_verify.verifier.verify(gold, answer, **kwargs)
    raise AttributeError("math_verify.verify not found")


def grade(gold: Any, answer: Any, **kwargs) -> Any:
    _ensure_math_verify()
    if hasattr(math_verify, "grade"):
        return math_verify.grade(gold, answer, **kwargs)
    if hasattr(math_verify, "grader") and hasattr(math_verify.grader, "verify"):
        return math_verify.grader.verify(gold, answer, **kwargs)
    if hasattr(math_verify, "verify"):
        return math_verify.verify(gold, answer, **kwargs)
    raise AttributeError("math_verify.grade not found")
