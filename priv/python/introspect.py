#!/usr/bin/env python3
"""
SnakeBridge v2 Python Module Introspector

Introspects Python modules to generate manifest data for SnakeBridge.
Outputs JSON to stdout containing module metadata, functions, classes, and type information.

Usage:
    python3 introspect.py <module_name> [--submodules MODULE1,MODULE2,...] [--flat]
    python3 introspect.py <module_name> --symbols '["sqrt","sin"]'
    python3 introspect.py <module_name> --attribute <attr_name>

Examples:
    python3 introspect.py math
    python3 introspect.py numpy --submodules linalg,fft,random
    python3 introspect.py json --flat
"""

import sys
import json
import inspect
import importlib
import types
import traceback
from typing import Any, Dict, List, Optional, get_type_hints, Union
import typing
import argparse

# Try to import docstring_parser for enhanced docstring parsing
try:
    from docstring_parser import parse as parse_docstring_lib
    HAS_DOCSTRING_PARSER = True
except ImportError:
    HAS_DOCSTRING_PARSER = False

PROTOCOL_DUNDERS = [
    "__str__", "__repr__", "__len__", "__getitem__", "__setitem__",
    "__contains__", "__iter__", "__next__", "__enter__", "__exit__",
    "__call__", "__hash__", "__eq__", "__ne__", "__lt__", "__le__",
    "__gt__", "__ge__", "__add__", "__sub__", "__mul__", "__truediv__"
]


def _docstring_text(obj: Any) -> str:
    doc = inspect.getdoc(obj) or ""
    return doc[:8000] if doc else ""


def _format_annotation(annotation: Any) -> Optional[str]:
    if annotation is inspect.Signature.empty:
        return None
    if hasattr(annotation, "__name__"):
        return annotation.__name__
    return str(annotation)


def type_to_dict(t: Any) -> Dict[str, Any]:
    """
    Convert a Python type annotation to a JSON-serializable dictionary.

    Args:
        t: Type annotation (can be a type, typing generic, etc.)

    Returns:
        Dictionary representation of the type
    """
    if t is None or t is type(None):
        return {"type": "none"}

    if t is inspect.Parameter.empty or t is inspect.Signature.empty:
        return {"type": "any"}
    if t is typing.Any:
        return {"type": "any"}

    # Handle basic types
    if t is int:
        return {"type": "int"}
    if t is float:
        return {"type": "float"}
    if t is str:
        return {"type": "string"}
    if t is bool:
        return {"type": "boolean"}
    if t is bytes:
        return {"type": "bytes"}
    if t is bytearray:
        return {"type": "bytearray"}
    if t is list:
        return {"type": "list"}
    if t is dict:
        return {"type": "dict"}
    if t is tuple:
        return {"type": "tuple"}
    if t is set:
        return {"type": "set"}
    if t is frozenset:
        return {"type": "frozenset"}

    # Handle typing module generics
    origin = typing.get_origin(t)
    args = typing.get_args(t)

    if origin is not None:
        # List[T]
        if origin is list:
            if args:
                return {"type": "list", "element_type": type_to_dict(args[0])}
            return {"type": "list"}

        # Dict[K, V]
        if origin is dict:
            if args and len(args) == 2:
                return {
                    "type": "dict",
                    "key_type": type_to_dict(args[0]),
                    "value_type": type_to_dict(args[1])
                }
            return {"type": "dict"}

        # Tuple[T1, T2, ...]
        if origin is tuple:
            if args:
                return {
                    "type": "tuple",
                    "element_types": [type_to_dict(arg) for arg in args]
                }
            return {"type": "tuple"}

        # Set[T]
        if origin is set:
            if args:
                return {"type": "set", "element_type": type_to_dict(args[0])}
            return {"type": "set"}

        # FrozenSet[T]
        if origin is frozenset:
            if args:
                return {"type": "frozenset", "element_type": type_to_dict(args[0])}
            return {"type": "frozenset"}

        # Union[T1, T2, ...] or Optional[T]
        if origin is Union:
            union_types = [type_to_dict(arg) for arg in args]
            # Check if it's Optional (Union with None)
            none_count = sum(1 for ut in union_types if ut.get("type") == "none")
            if none_count == 1 and len(union_types) == 2:
                other_type = next(ut for ut in union_types if ut.get("type") != "none")
                return {"type": "optional", "inner_type": other_type}
            return {"type": "union", "types": union_types}

        # Other generic types
        return {"type": "generic", "origin": str(origin), "args": [type_to_dict(arg) for arg in args]}

    # Handle class types
    if inspect.isclass(t):
        name = t.__name__
        module = t.__module__
        type_name = name.lower()

        if "numpy" in module and "ndarray" in type_name:
            return {"type": "numpy.ndarray"}
        if "numpy" in module and "dtype" in type_name:
            return {"type": "numpy.dtype"}
        if "torch" in module and "tensor" in name:
            return {"type": "torch.Tensor"}
        if "torch" in module and "dtype" in type_name:
            return {"type": "torch.dtype"}
        if "pandas" in module and "dataframe" in type_name:
            return {"type": "pandas.DataFrame"}
        if "pandas" in module and "series" in type_name:
            return {"type": "pandas.Series"}

        return {"type": "class", "name": name, "module": module}

    # Fallback to string representation
    return {"type": "any", "raw": str(t)}


def _param_info(param: inspect.Parameter, type_hint: Any = None) -> Dict[str, Any]:
    info = {"name": param.name, "kind": param.kind.name}
    if param.default is not inspect.Parameter.empty:
        info["default"] = repr(param.default)
    if param.annotation is not inspect.Parameter.empty:
        info["annotation"] = _format_annotation(param.annotation)

    type_annotation = type_hint if type_hint is not None else param.annotation
    info["type"] = type_to_dict(type_annotation)
    return info


def _introspect_callable_symbol(name: str, obj: Any, module_name: str) -> Dict[str, Any]:
    info = {
        "name": name,
        "type": "function",
        "callable": callable(obj),
        "module": module_name,
        "python_module": module_name,
    }

    try:
        sig = inspect.signature(obj)
        info["signature_available"] = True
        try:
            type_hints = typing.get_type_hints(obj)
        except Exception:
            type_hints = {}

        info["parameters"] = [
            _param_info(p, type_hints.get(p.name))
            for p in sig.parameters.values()
        ]

        if sig.return_annotation is not inspect.Signature.empty:
            info["return_annotation"] = _format_annotation(sig.return_annotation)
        info["return_type"] = type_to_dict(type_hints.get("return", sig.return_annotation))
    except (ValueError, TypeError):
        info["signature_available"] = False
        info["parameters"] = []
        info["return_type"] = {"type": "any"}

    doc = _docstring_text(obj)
    if doc:
        info["docstring"] = doc
    return info


def _introspect_attribute_symbol(name: str, obj: Any, module_name: str) -> Dict[str, Any]:
    info = {
        "name": name,
        "type": "attribute",
        "module": module_name,
        "python_module": module_name,
        "signature_available": True,
        "parameters": [],
        "return_type": type_to_dict(type(obj)),
    }

    doc = _docstring_text(obj)
    if doc:
        info["docstring"] = doc
    return info


def _introspect_class_symbol(name: str, cls: type) -> Dict[str, Any]:
    methods: List[Dict[str, Any]] = []
    dunder_methods: List[str] = []

    for method_name, method in inspect.getmembers(cls, predicate=callable):
        if method_name.startswith("__") and method_name not in ["__init__"]:
            if method_name in PROTOCOL_DUNDERS:
                dunder_methods.append(method_name)
            continue
        try:
            sig = inspect.signature(method)
            signature_available = True
            try:
                type_hints = typing.get_type_hints(method)
            except Exception:
                type_hints = {}

            params = [
                _param_info(p, type_hints.get(p.name))
                for p in sig.parameters.values()
                if p.name != "self"
            ]
            return_type = type_to_dict(type_hints.get("return", sig.return_annotation))
        except (ValueError, TypeError):
            signature_available = False
            params = []
            return_type = {"type": "any"}

        methods.append({
            "name": method_name,
            "parameters": params,
            "docstring": _docstring_text(method),
            "return_type": return_type,
            "signature_available": signature_available,
        })

    attributes: List[str] = []
    for attr_name, value in inspect.getmembers(cls):
        if attr_name.startswith("__"):
            continue
        if callable(value):
            continue
        attributes.append(attr_name)

    return {
        "name": name,
        "type": "class",
        "python_module": cls.__module__,
        "docstring": _docstring_text(cls),
        "methods": methods,
        "attributes": attributes,
        "dunder_methods": dunder_methods,
    }


def introspect_symbols(module_name: str, symbols: List[str]) -> List[Dict[str, Any]]:
    module = importlib.import_module(module_name)
    results = []
    for name in symbols:
        obj = getattr(module, name, None)
        if obj is None:
            results.append({"name": name, "error": "not_found"})
            continue

        if inspect.isclass(obj):
            results.append(_introspect_class_symbol(name, obj))
        elif callable(obj):
            results.append(_introspect_callable_symbol(name, obj, module_name))
        else:
            results.append(_introspect_attribute_symbol(name, obj, module_name))
    return results


def introspect_attribute_info(module_path: str, attr_name: str) -> Dict[str, Any]:
    try:
        module = importlib.import_module(module_path)
        attr = getattr(module, attr_name, None)

        if attr is None:
            return {"exists": False}

        return {
            "exists": True,
            "is_class": inspect.isclass(attr),
            "is_module": inspect.ismodule(attr),
            "is_function": inspect.isfunction(attr) or inspect.isbuiltin(attr),
            "type_name": type(attr).__name__,
        }
    except Exception as e:
        return {"error": str(e)}


def _parse_symbols_arg(value: Optional[str]) -> List[str]:
    if not value:
        return []
    value = value.strip()
    if value.startswith("["):
        try:
            parsed = json.loads(value)
            return [str(item) for item in parsed]
        except Exception:
            pass
    return [item.strip() for item in value.split(",") if item.strip()]


def parse_docstring(docstring: Optional[str]) -> Dict[str, Any]:
    """
    Parse a docstring into structured data.

    Args:
        docstring: The docstring to parse

    Returns:
        Dictionary with parsed docstring information
    """
    if not docstring:
        return {
            "summary": None,
            "description": None,
            "params": [],
            "returns": None,
            "raises": []
        }

    if HAS_DOCSTRING_PARSER:
        try:
            parsed = parse_docstring_lib(docstring)
            return {
                "summary": parsed.short_description,
                "description": parsed.long_description,
                "params": [
                    {
                        "name": param.arg_name,
                        "description": param.description,
                        "type": param.type_name
                    }
                    for param in parsed.params
                ],
                "returns": {
                    "description": parsed.returns.description if parsed.returns else None,
                    "type": parsed.returns.type_name if parsed.returns else None
                } if parsed.returns else None,
                "raises": [
                    {
                        "exception": exc.type_name,
                        "description": exc.description
                    }
                    for exc in parsed.raises
                ]
            }
        except Exception:
            # Fall through to simple parsing
            pass

    # Simple parsing - just split by lines and get the first line as summary
    lines = docstring.strip().split('\n')
    summary = lines[0].strip() if lines else None
    description = '\n'.join(line.strip() for line in lines[1:]).strip() if len(lines) > 1 else None

    return {
        "summary": summary or None,
        "description": description or None,
        "params": [],
        "returns": None,
        "raises": [],
        "raw": docstring
    }


def introspect_parameter(param: inspect.Parameter, type_hint: Any = None) -> Dict[str, Any]:
    """
    Introspect a function parameter.

    Args:
        param: The parameter to introspect
        type_hint: Type hint from get_type_hints, if available

    Returns:
        Dictionary with parameter information
    """
    param_info = {
        "name": param.name,
        "kind": param.kind.name.lower()
    }

    # Use type hint if available, otherwise use annotation
    type_annotation = type_hint if type_hint is not None else param.annotation
    param_info["type"] = type_to_dict(type_annotation)

    # Handle default values
    if param.default is not inspect.Parameter.empty:
        try:
            # Try to serialize the default value
            if param.default is None:
                param_info["default"] = None
            elif isinstance(param.default, (int, float, str, bool)):
                param_info["default"] = param.default
            elif isinstance(param.default, (list, tuple, dict, set)):
                param_info["default"] = str(param.default)
            else:
                param_info["default"] = repr(param.default)
        except Exception:
            param_info["default"] = "<non-serializable>"

    return param_info


def introspect_function(name: str, func: Any) -> Dict[str, Any]:
    """
    Introspect a function or method.

    Args:
        name: Name of the function
        func: The function object

    Returns:
        Dictionary with function information
    """
    func_info = {
        "name": name,
        "type": "function"
    }

    # Get docstring
    docstring = inspect.getdoc(func)
    func_info["docstring"] = parse_docstring(docstring)

    try:
        # Get signature
        sig = inspect.signature(func)
        func_info["signature_available"] = True

        # Get type hints
        try:
            type_hints = get_type_hints(func)
        except Exception:
            type_hints = {}

        # Introspect parameters
        func_info["parameters"] = [
            introspect_parameter(param, type_hints.get(param_name))
            for param_name, param in sig.parameters.items()
        ]

        # Introspect return type
        return_annotation = type_hints.get('return', sig.return_annotation)
        func_info["return_type"] = type_to_dict(return_annotation)

    except (ValueError, TypeError) as e:
        # Some built-in functions don't have accessible signatures
        func_info["signature_available"] = False
        func_info["parameters"] = []
        func_info["return_type"] = {"type": "any"}
        func_info["error"] = f"Could not introspect signature: {str(e)}"

    return func_info


def introspect_class(name: str, cls: type) -> Dict[str, Any]:
    """
    Introspect a class.

    Args:
        name: Name of the class
        cls: The class object

    Returns:
        Dictionary with class information
    """
    class_info = {
        "name": name,
        "type": "class"
    }

    # Get docstring
    docstring = inspect.getdoc(cls)
    class_info["docstring"] = parse_docstring(docstring)

    # Get base classes
    try:
        bases = [base.__name__ for base in cls.__bases__ if base is not object]
        if bases:
            class_info["bases"] = bases
    except Exception:
        pass

    # Introspect methods
    methods = []
    for method_name, method in inspect.getmembers(cls, inspect.isfunction):
        # Skip private methods unless they're special methods
        if method_name.startswith('_') and not method_name.startswith('__'):
            continue

        try:
            method_info = introspect_function(method_name, method)
            method_info["type"] = "method"
            methods.append(method_info)
        except Exception:
            # Skip methods that can't be introspected
            pass

    if methods:
        class_info["methods"] = methods

    # Introspect properties
    properties = []
    for prop_name, prop in inspect.getmembers(cls):
        if isinstance(prop, property):
            prop_info = {
                "name": prop_name,
                "type": "property"
            }
            if prop.fget:
                doc = inspect.getdoc(prop.fget)
                if doc:
                    prop_info["docstring"] = parse_docstring(doc)
            properties.append(prop_info)

    if properties:
        class_info["properties"] = properties

    return class_info


def introspect_attribute(name: str, value: Any) -> Dict[str, Any]:
    """
    Introspect a non-callable module attribute.

    Args:
        name: Attribute name
        value: Attribute value

    Returns:
        Dictionary with attribute information
    """
    attr_info = {
        "name": name,
        "type": "attribute",
        "return_type": type_to_dict(type(value))
    }

    docstring = inspect.getdoc(value)
    if docstring:
        attr_info["docstring"] = parse_docstring(docstring)

    return attr_info


def get_object_namespace(obj: Any, base_module: str) -> str:
    """
    Determine the namespace of an object relative to the base module.

    Args:
        obj: The object to check
        base_module: The base module name (e.g., "numpy")

    Returns:
        Namespace string (e.g., "" for base, "linalg" for numpy.linalg)
    """
    try:
        obj_module = getattr(obj, '__module__', None)
        if not obj_module:
            return ""

        # If the object is from the base module, return empty string
        if obj_module == base_module:
            return ""

        # If it's from a submodule, extract the submodule part
        if obj_module.startswith(base_module + '.'):
            namespace = obj_module[len(base_module) + 1:]
            return namespace

        return ""
    except Exception:
        return ""


def introspect_module_namespace(module_name: str, namespace: str = "") -> Dict[str, Any]:
    """
    Introspect a Python module or submodule.

    Args:
        module_name: Full module name to introspect (e.g., "numpy.linalg")
        namespace: Namespace label (e.g., "linalg")

    Returns:
        Dictionary with namespace information
    """
    try:
        module = importlib.import_module(module_name)
    except ImportError as e:
        sys.stderr.write(f"Warning: Failed to import module '{module_name}': {str(e)}\n")
        return None

    namespace_info = {
        "functions": [],
        "classes": [],
        "attributes": []
    }

    # Get the module's __all__ if available (explicit public API)
    module_all = getattr(module, '__all__', None)

    # Introspect all public members
    for name, obj in inspect.getmembers(module):
        # Skip private members
        if name.startswith('_'):
            continue

        # Determine if this item should be included
        should_include = False

        if module_all is not None:
            # If __all__ exists, only include items in __all__
            should_include = name in module_all
        else:
            # No __all__, use heuristics
            try:
                obj_module = getattr(obj, '__module__', None)

                if obj_module:
                    # For submodules, include if the object is from this exact module
                    # or from any of its submodules
                    if obj_module == module_name or obj_module.startswith(module_name + '.'):
                        should_include = True
                else:
                    # Objects without __module__ (builtins) - only include in base module
                    if not namespace:
                        should_include = True
            except Exception:
                # If we can't determine, only include for base module
                should_include = not namespace

        if not should_include:
            continue

        try:
            if inspect.isclass(obj):
                class_info = introspect_class(name, obj)
                namespace_info["classes"].append(class_info)
            elif inspect.isfunction(obj) or inspect.isbuiltin(obj) or (callable(obj) and not inspect.isclass(obj)):
                # Include functions, builtins, and other callable objects (like numpy's _ArrayFunctionDispatcher)
                func_info = introspect_function(name, obj)
                namespace_info["functions"].append(func_info)
            elif not inspect.ismodule(obj):
                attr_info = introspect_attribute(name, obj)
                namespace_info["attributes"].append(attr_info)
        except Exception as e:
            # Log the error but continue processing
            sys.stderr.write(f"Warning: Failed to introspect {name} in {module_name}: {str(e)}\n")
            continue

    return namespace_info


def introspect_module(module_name: str, submodules: Optional[List[str]] = None, flat_mode: bool = False) -> Dict[str, Any]:
    """
    Introspect a Python module with optional submodule detection.

    Args:
        module_name: Name of the module to introspect
        submodules: List of submodule names to also introspect (e.g., ["linalg", "fft"])
        flat_mode: If True, use legacy flat format (v2.0), otherwise use namespaced format (v2.1)

    Returns:
        Dictionary with complete module information
    """
    try:
        module = importlib.import_module(module_name)
    except ImportError as e:
        return {
            "error": f"Failed to import module '{module_name}': {str(e)}",
            "module": module_name
        }

    # Get module version if available
    module_version = getattr(module, '__version__', None)

    # Get module docstring
    module_doc = inspect.getdoc(module)

    # Get module file path
    module_file = module.__file__ if hasattr(module, '__file__') else None

    if flat_mode:
        # Legacy flat format (v2.0)
        module_info = {
            "module": module_name,
            "version": "2.0",
            "functions": [],
            "classes": [],
            "attributes": []
        }

        if module_doc:
            module_info["docstring"] = parse_docstring(module_doc)

        if module_version:
            module_info["module_version"] = module_version

        if module_file:
            module_info["file"] = module_file

        # Get the module's __all__ if available (explicit public API)
        module_all = getattr(module, '__all__', None)

        # Introspect all public members
        for name, obj in inspect.getmembers(module):
            # Skip private members
            if name.startswith('_'):
                continue

            # Determine if this item should be included
            should_include = False

            if module_all is not None:
                # If __all__ exists, only include items in __all__
                should_include = name in module_all
            else:
                # No __all__, use heuristics: include if defined in this module
                try:
                    obj_module = getattr(obj, '__module__', None)
                    # Include if defined in this module or its submodules
                    if obj_module and (obj_module == module_name or obj_module.startswith(module_name + '.')):
                        should_include = True
                    # Also include built-in functions that don't have __module__
                    elif obj_module is None:
                        should_include = True
                except Exception:
                    should_include = True  # Include if we can't determine

            if not should_include:
                continue

            try:
                if inspect.isclass(obj):
                    class_info = introspect_class(name, obj)
                    module_info["classes"].append(class_info)
                elif inspect.isfunction(obj) or inspect.isbuiltin(obj) or (callable(obj) and not inspect.isclass(obj)):
                    # Include functions, builtins, and other callable objects (like numpy's _ArrayFunctionDispatcher)
                    func_info = introspect_function(name, obj)
                    module_info["functions"].append(func_info)
                elif not inspect.ismodule(obj):
                    attr_info = introspect_attribute(name, obj)
                    module_info["attributes"].append(attr_info)
            except Exception as e:
                # Log the error but continue processing
                sys.stderr.write(f"Warning: Failed to introspect {name}: {str(e)}\n")
                continue

        return module_info

    else:
        # New namespaced format (v2.1)
        module_info = {
            "module": module_name,
            "version": "2.1",
            "namespaces": {}
        }

        if module_doc:
            module_info["docstring"] = parse_docstring(module_doc)

        if module_version:
            module_info["module_version"] = module_version

        if module_file:
            module_info["file"] = module_file

        # Introspect base module (namespace "")
        base_namespace = introspect_module_namespace(module_name, "")
        if base_namespace:
            module_info["namespaces"][""] = base_namespace

        # Introspect submodules if requested
        if submodules:
            for submodule in submodules:
                full_module_name = f"{module_name}.{submodule}"
                namespace_info = introspect_module_namespace(full_module_name, submodule)
                if namespace_info:
                    module_info["namespaces"][submodule] = namespace_info

        return module_info


def main():
    """Main entry point for the introspection script."""
    parser = argparse.ArgumentParser(
        description='Introspect Python modules for SnakeBridge',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 introspect.py json
  python3 introspect.py numpy --submodules linalg,fft,random
  python3 introspect.py numpy --flat
        """
    )

    parser.add_argument('module', nargs='?', help='Name of the Python module to introspect')
    parser.add_argument(
        '--module',
        dest='module_flag',
        help='Name of the Python module to introspect'
    )
    parser.add_argument(
        '--submodules',
        help='Comma-separated list of submodules to introspect (e.g., linalg,fft,random)',
        default=None
    )
    parser.add_argument(
        '--symbols',
        help='JSON array or comma-separated list of symbols to introspect',
        default=None
    )
    parser.add_argument(
        '--attribute',
        help='Single attribute name to introspect',
        default=None
    )
    parser.add_argument(
        '--flat',
        action='store_true',
        help='Use legacy flat format (v2.0) instead of namespaced format (v2.1)'
    )

    args = parser.parse_args()

    module_name = args.module_flag or args.module
    if not module_name:
        parser.error("module name is required")
    submodules = args.submodules.split(',') if args.submodules else None
    flat_mode = args.flat

    try:
        if args.attribute:
            result = introspect_attribute_info(module_name, args.attribute)
            print(json.dumps(result))
        elif args.symbols:
            symbols = _parse_symbols_arg(args.symbols)
            result = introspect_symbols(module_name, symbols)
            print(json.dumps(result))
        else:
            result = introspect_module(module_name, submodules=submodules, flat_mode=flat_mode)
            print(json.dumps(result, indent=2))
    except Exception as e:
        traceback.print_exc(file=sys.stderr)
        error_result = {
            "error": f"Introspection failed: {str(e)}",
            "module": module_name
        }
        print(json.dumps(error_result, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
