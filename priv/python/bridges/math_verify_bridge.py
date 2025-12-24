"""
math-verify helper functions for SnakeBridge.

Thin wrappers that normalize the most common API entry points.
"""

import sys
from typing import Any

# Add parent directory to path for bridge_base import
sys.path.insert(0, str(__file__).rsplit("/bridges", 1)[0])

from snakebridge_adapter.bridge_base import make_import_guard

# Import guard
math_verify, HAS_MATH_VERIFY, _ensure_math_verify = make_import_guard("math_verify", "math-verify")


# Public API functions

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
