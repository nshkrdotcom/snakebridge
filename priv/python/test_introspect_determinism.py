"""Regression tests for deterministic introspection metadata."""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import introspect


def test_stable_repr_removes_process_local_object_address():
    matcher = re.compile("snakebridge").match

    raw = repr(matcher)
    stable = introspect._stable_repr(matcher)

    assert "built-in method match" in raw
    assert "built-in method match" in stable

    assert re.search(
        r" at 0x[0-9a-fA-F]+(?=>+$)",
        raw,
    )

    assert not re.search(
        r" at 0x[0-9a-fA-F]+(?=>+$)",
        stable,
    )


def test_stable_repr_preserves_literal_string():
    value = "<literal at 0x1234>"

    assert introspect._stable_repr(value) == repr(value)


def test_stable_repr_preserves_normal_defaults():
    assert introspect._stable_repr(None) == "None"
    assert introspect._stable_repr(False) == "False"
    assert introspect._stable_repr(20) == "20"
    assert introspect._stable_repr("hello") == "'hello'"
    assert introspect._stable_repr([1, 2, 3]) == "[1, 2, 3]"
