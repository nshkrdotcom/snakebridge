"""Local module for strict mode example."""


def add(a, b):
    return a + b


def multiply(a, b):
    return a * b


def mystery(value):
    return value


mystery.__signature__ = "invalid"
