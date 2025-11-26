"""
Simple Python module used by real Python integration tests.

Provides a small Greeter class so tests can verify class creation and
method invocation through SnakeBridge.
"""


class Greeter:
    """Tiny class with predictable behavior for integration tests."""

    def __init__(self, name: str = "SnakeBridge"):
        self.name = name

    def greet(self) -> str:
        """Return a friendly greeting."""
        return f"Hello from {self.name}"

    def repeat_phrase(self, phrase: str, times: int = 1) -> str:
        """Repeat a phrase a number of times separated by spaces."""
        times = max(1, int(times))
        return " ".join([phrase] * times)

