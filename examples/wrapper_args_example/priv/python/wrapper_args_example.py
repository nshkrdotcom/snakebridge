"""Local module for wrapper args example."""


def _flatten(values):
    for item in values:
        if isinstance(item, (list, tuple)):
            for inner in item:
                yield inner
        else:
            yield item


def mean(values, axis=None, dtype=None, keepdims=False):
    """
    Compute a simple mean with optional axis and dtype placeholders.
    """
    if values is None:
        return None

    if axis is None:
        items = list(_flatten(values))
        if not items:
            return 0.0
        result = sum(items) / float(len(items))
    else:
        matrix = list(values)
        if not matrix:
            result = []
        elif axis == 0:
            cols = list(zip(*matrix))
            result = [sum(col) / float(len(col)) for col in cols]
        elif axis == 1:
            result = [sum(row) / float(len(row)) for row in matrix]
        else:
            raise ValueError("Unsupported axis")

    if keepdims:
        return [result]

    return result


def join_values(*values, sep=" "):
    """Join values with a separator, demonstrating Python varargs."""
    return sep.join(str(v) for v in values)
