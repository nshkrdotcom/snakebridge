#!/usr/bin/env python3
"""
Type extractor for SnakeBridge.

Extracts Python type hints and converts them to a JSON format that can be
mapped to Elixir typespecs.
"""

import typing
import inspect
import json
from typing import get_type_hints, get_origin, get_args, Any, Optional
import sys


def extract_type_info(obj) -> dict:
    """
    Extracts type information from a Python callable.

    Returns a dict with:
    - parameters: dict of parameter name -> type info
    - return_type: type info for return
    - confidence: "declared" if from annotations, "unknown" otherwise
    """
    try:
        hints = get_type_hints(obj)
    except Exception:
        hints = getattr(obj, '__annotations__', {})

    sig = inspect.signature(obj) if callable(obj) else None

    params = {}
    if sig:
        for name, param in sig.parameters.items():
            if name in hints:
                params[name] = serialize_type(hints[name])
            else:
                params[name] = {"type": "any", "confidence": "unknown"}

    return_type = None
    if 'return' in hints:
        return_type = serialize_type(hints['return'])

    return {
        "parameters": params,
        "return_type": return_type,
        "confidence": "declared" if hints else "unknown"
    }


def serialize_type(t) -> dict:
    """
    Serializes a Python type to a JSON-compatible dict.

    Handles:
    - Basic types (int, float, str, bool, bytes, None)
    - Collection types (list, dict, tuple, set)
    - Union and Optional types
    - ML library types (numpy, torch, pandas)
    - Generic types
    """
    if t is type(None):
        return {"type": "none"}

    if t is Any:
        return {"type": "any"}

    origin = get_origin(t)
    args = get_args(t)

    # Handle basic types
    type_map = {
        int: "int",
        float: "float",
        bool: "bool",
        str: "str",
        bytes: "bytes",
        list: "list",
        dict: "dict",
        set: "set",
        tuple: "tuple",
    }

    if t in type_map:
        return {"type": type_map[t]}

    # Handle typing generics
    if origin is list:
        if args:
            return {"type": "list", "element_type": serialize_type(args[0])}
        return {"type": "list"}

    if origin is dict:
        if len(args) == 2:
            return {
                "type": "dict",
                "key_type": serialize_type(args[0]),
                "value_type": serialize_type(args[1])
            }
        return {"type": "dict"}

    if origin is set:
        if args:
            return {"type": "set", "element_type": serialize_type(args[0])}
        return {"type": "set"}

    if origin is tuple:
        if args:
            if len(args) == 2 and args[1] is ...:
                return {"type": "tuple", "element_type": serialize_type(args[0]), "variadic": True}
            return {"type": "tuple", "element_types": [serialize_type(a) for a in args]}
        return {"type": "tuple"}

    if origin is typing.Union:
        if len(args) == 2 and type(None) in args:
            # Optional[T]
            non_none = [a for a in args if a is not type(None)][0]
            return {"type": "optional", "inner_type": serialize_type(non_none)}
        return {"type": "union", "types": [serialize_type(a) for a in args]}

    # Handle special ML types
    type_name = getattr(t, '__name__', str(t))
    module = getattr(t, '__module__', '')

    if 'numpy' in module:
        if 'ndarray' in type_name.lower():
            return {"type": "numpy.ndarray"}
        if 'dtype' in type_name.lower():
            return {"type": "numpy.dtype"}

    if 'torch' in module:
        if 'Tensor' in type_name:
            return {"type": "torch.Tensor"}
        if 'dtype' in type_name.lower():
            return {"type": "torch.dtype"}

    if 'pandas' in module:
        if 'DataFrame' in type_name:
            return {"type": "pandas.DataFrame"}
        if 'Series' in type_name:
            return {"type": "pandas.Series"}

    # Fallback: use class representation
    return {"type": "class", "name": type_name, "module": module}


def extract_module_types(module_name: str) -> dict:
    """
    Extracts type info for all public callables in a module.

    Returns a dict of function_name -> type_info.
    """
    import importlib
    module = importlib.import_module(module_name)

    result = {}
    for name in dir(module):
        if name.startswith('_'):
            continue

        obj = getattr(module, name)
        if callable(obj):
            try:
                result[name] = extract_type_info(obj)
            except Exception:
                result[name] = {"confidence": "unknown"}

    return result


def extract_function_types(module_name: str, function_name: str) -> dict:
    """
    Extracts type info for a specific function in a module.
    """
    import importlib
    module = importlib.import_module(module_name)
    func = getattr(module, function_name)
    return extract_type_info(func)


if __name__ == '__main__':
    if len(sys.argv) == 2:
        # Extract all functions from module
        module_name = sys.argv[1]
        result = extract_module_types(module_name)
        print(json.dumps(result, indent=2))
    elif len(sys.argv) == 3:
        # Extract specific function
        module_name = sys.argv[1]
        function_name = sys.argv[2]
        result = extract_function_types(module_name, function_name)
        print(json.dumps(result, indent=2))
    else:
        print("Usage: type_extractor.py <module_name> [function_name]", file=sys.stderr)
        sys.exit(1)
