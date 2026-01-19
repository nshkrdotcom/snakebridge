"""Module that should fall back to variadic signature."""


def variadic_only(*args, **kwargs):
    return args


# Force signature resolution failures.
variadic_only.__signature__ = "invalid"
variadic_only.__annotations__ = {}
