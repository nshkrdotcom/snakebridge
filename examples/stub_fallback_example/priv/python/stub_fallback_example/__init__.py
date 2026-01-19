"""Runtime module for stub fallback example."""


def stubbed(a, b=1):
    return a + b


stubbed.__signature__ = "invalid"
