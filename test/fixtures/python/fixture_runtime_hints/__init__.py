"""Runtime type hints fixture module."""


def hint_only(a: int, b: str) -> bool:
    return bool(a) and bool(b)


# Force inspect.signature to fail so runtime hints are used.
hint_only.__signature__ = "invalid"

def structured_defaults(
    required: "UnresolvedType",
    optional: "UnresolvedType" = None,
    *,
    mode: "UnresolvedType" = None,
) -> "UnresolvedType":
    """Keep inspect.signature defaults/kinds even when hints cannot resolve."""
    return required if optional is None else optional


class StructuredDefaultsClass:
    def __init__(
        self,
        signature: "UnresolvedType",
        max_iters: "UnresolvedType" = 20,
        *,
        mode: "UnresolvedType" = None,
    ):
        self.signature = signature
        self.max_iters = max_iters
        self.mode = mode
