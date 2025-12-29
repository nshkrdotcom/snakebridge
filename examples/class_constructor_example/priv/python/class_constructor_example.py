"""Local module for class constructor example."""


class EmptyClass:
    """A class with no __init__ arguments."""

    def __init__(self):
        self.created = True


class Point:
    """A class with two required __init__ arguments."""

    def __init__(self, x, y):
        self.x = x
        self.y = y

    def magnitude(self):
        return (self.x ** 2 + self.y ** 2) ** 0.5


class Config:
    """A class with an optional __init__ argument."""

    def __init__(self, path, readonly=False):
        self.path = path
        self.readonly = readonly

    def summary(self):
        return f"{self.path} (readonly={self.readonly})"
