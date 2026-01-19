"""Runtime type hints fixture module."""


def hint_only(a: int, b: str) -> bool:
    return bool(a) and bool(b)


# Force inspect.signature to fail so runtime hints are used.
hint_only.__signature__ = "invalid"
