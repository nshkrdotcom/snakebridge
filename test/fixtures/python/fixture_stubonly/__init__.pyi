"""Stub-only module docs."""


def stub_add(a: int, b: int) -> int: ...


def stub_doc_only(a: int) -> int:
    """Docstring from stub only."""
    ...


class StubClass:
    """Stub class docs."""

    def __init__(self, value: int) -> None: ...

    def echo(self, text: str) -> str: ...
