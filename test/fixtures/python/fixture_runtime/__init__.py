"""Runtime fixture module."""


def add(a, b):
    """Add two numbers."""
    return a + b


def greet(name: str, excited: bool = False) -> str:
    """Return a greeting."""
    suffix = "!" if excited else "."
    return f"Hello, {name}{suffix}"


class Greeter:
    """Greeter class."""

    def __init__(self, prefix: str):
        self.prefix = prefix

    def hello(self, name: str) -> str:
        """Say hello."""
        return f"{self.prefix}, {name}"
