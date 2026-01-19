"""Local module for coverage report example."""


def documented(a, b):
    """Add two numbers."""
    return a + b


def undocumented(value):
    return value * 2


class Example:
    """Example class for coverage reporting."""

    def __init__(self, value):
        self.value = value

    def increment(self, delta):
        """Increase value by delta."""
        return self.value + delta
