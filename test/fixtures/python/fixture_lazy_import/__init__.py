"""
Test fixture for lazy import handling.

This module mimics the pattern used by vllm and other libraries
that use __getattr__ for lazy imports. The classes in __all__
are not directly accessible via dir() or inspect.getmembers()
until they are explicitly accessed by name.
"""

__all__ = ["LazyClass", "LazyParams", "eager_function"]

# This dict maps names to their actual module paths
_LAZY_IMPORTS = {
    "LazyClass": "_lazy_class",
    "LazyParams": "_lazy_params",
}


def __getattr__(name: str):
    """Lazy import handler - only loads modules when accessed."""
    if name in _LAZY_IMPORTS:
        import importlib
        submodule = _LAZY_IMPORTS[name]
        module = importlib.import_module(f".{submodule}", __package__)
        cls = getattr(module, name)
        # Cache it in the module namespace
        globals()[name] = cls
        return cls
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


def eager_function(x: int, y: int) -> int:
    """An eagerly-loaded function that should always be visible."""
    return x + y
