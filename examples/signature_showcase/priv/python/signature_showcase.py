def optional_args(a, b=1, c=2):
    return {"a": a, "b": b, "c": c}


def keyword_only(a, *, required_kw, optional_kw=None):
    return {"a": a, "required_kw": required_kw, "optional_kw": optional_kw}


def variadic(*args, **kwargs):
    return {"args": list(args), "kwargs": kwargs}


variadic.__signature__ = "unavailable"


def class_():
    return "reserved-name"


globals()["class"] = class_
