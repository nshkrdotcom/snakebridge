"""Module for stubgen fallback tests."""


def generated(a: int, b: int = 1, *args, **kwargs) -> int:
    return a + b


# Force inspect.signature to fail when runtime source is used.
generated.__signature__ = "invalid"
