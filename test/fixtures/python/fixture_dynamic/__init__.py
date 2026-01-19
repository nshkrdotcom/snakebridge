"""Dynamic symbol fixture module."""

__all__ = ["dynamic"]


def __getattr__(name):
    if name == "dynamic":
        def dynamic(x, y=1):
            return x + y
        return dynamic
    raise AttributeError(name)
