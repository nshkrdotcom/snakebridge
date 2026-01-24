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
import importlib.util
import types
import os
import ast
import pkgutil
import subprocess
import fnmatch
from typing import Any, Dict, List, Optional, Tuple, Union, get_type_hints
import typing
import argparse

try:
    import importlib.metadata as importlib_metadata
except Exception:  # pragma: no cover
    import importlib_metadata

try:
    import libcst as cst
except ImportError:
    cst = None

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

DEFAULT_SIGNATURE_SOURCES = [
    "runtime",
    "text_signature",
    "runtime_hints",
    "stub",
    "stubgen",
    "variadic",
]

DEFAULT_CLASS_METHOD_SCOPE = "all"
DEFAULT_MAX_CLASS_METHODS = 1000

_STUB_CACHE: Dict[str, Dict[str, Any]] = {}
_STUBGEN_CACHE: Dict[str, Dict[str, Any]] = {}


def _normalize_signature_sources(sources: Optional[List[str]]) -> List[str]:
    if not sources:
        return list(DEFAULT_SIGNATURE_SOURCES)
    return [str(source) for source in sources]


def _parse_config(config_json: Optional[str]) -> Dict[str, Any]:
    if not config_json:
        return {
            "signature_sources": list(DEFAULT_SIGNATURE_SOURCES),
            "stub_search_paths": [],
            "use_typeshed": False,
            "typeshed_path": None,
            "stubgen": {"enabled": True},
            "class_method_scope": DEFAULT_CLASS_METHOD_SCOPE,
            "max_class_methods": DEFAULT_MAX_CLASS_METHODS,
        }

    try:
        raw = json.loads(config_json)
    except Exception:
        raw = {}

    signature_sources = _normalize_signature_sources(raw.get("signature_sources"))
    stub_search_paths = raw.get("stub_search_paths") or []
    stub_search_paths = [str(path) for path in stub_search_paths if path]
    use_typeshed = bool(raw.get("use_typeshed", False))
    typeshed_path = raw.get("typeshed_path")
    stubgen = raw.get("stubgen") or {}

    class_method_scope = raw.get("class_method_scope")
    if class_method_scope is None:
        class_method_scope = DEFAULT_CLASS_METHOD_SCOPE
    class_method_scope = str(class_method_scope).lower()
    if class_method_scope not in ("all", "defined"):
        class_method_scope = DEFAULT_CLASS_METHOD_SCOPE

    raw_max_class_methods = raw.get("max_class_methods")
    if raw_max_class_methods is None:
        max_class_methods = DEFAULT_MAX_CLASS_METHODS
    else:
        try:
            max_class_methods = int(raw_max_class_methods)
        except Exception:
            max_class_methods = DEFAULT_MAX_CLASS_METHODS

    # Allow disabling guardrails with <= 0
    if isinstance(max_class_methods, int) and max_class_methods <= 0:
        max_class_methods = None

    return {
        "signature_sources": signature_sources,
        "stub_search_paths": stub_search_paths,
        "use_typeshed": use_typeshed,
        "typeshed_path": typeshed_path,
        "stubgen": stubgen,
        "class_method_scope": class_method_scope,
        "max_class_methods": max_class_methods,
    }


def _iter_class_method_pairs(
    cls: type,
    scope: str,
    max_methods: Optional[int],
) -> Tuple[List[Tuple[str, Any]], List[str], bool, str]:
    """
    Returns (method_pairs, protocol_dunders, methods_truncated, effective_scope).

    - method_pairs: callables that will become generated wrappers (excluding most dunders)
    - protocol_dunders: protocol dunder names discovered (kept for reference)
    - methods_truncated: true when we hit the max_methods guardrail in scope=all
    - effective_scope: "all" or "defined"
    """
    protocol_dunders: List[str] = []

    def include_name(name: str) -> bool:
        if name.startswith("__") and name != "__init__":
            if name in PROTOCOL_DUNDERS:
                protocol_dunders.append(name)
            return False
        return True

    def iter_names_defined() -> List[str]:
        names = list(cls.__dict__.keys())
        if "__init__" not in cls.__dict__ and hasattr(cls, "__init__"):
            names.append("__init__")
        return sorted(set(names))

    def iter_names_all() -> List[str]:
        # dir() is deterministic and includes inherited members
        return [name for name in dir(cls)]

    def build_pairs(names: List[str], limit: Optional[int]) -> Tuple[List[Tuple[str, Any]], bool]:
        pairs: List[Tuple[str, Any]] = []
        exceeded = False

        for name in names:
            if not include_name(name):
                continue

            try:
                value = getattr(cls, name)
            except Exception:
                continue

            if not callable(value):
                continue

            pairs.append((name, value))

            if limit is not None and len(pairs) > limit:
                exceeded = True
                break

        return pairs, exceeded

    scope = (scope or DEFAULT_CLASS_METHOD_SCOPE).lower()
    if scope not in ("all", "defined"):
        scope = DEFAULT_CLASS_METHOD_SCOPE

    if scope == "defined":
        pairs, _ = build_pairs(iter_names_defined(), None)
        return pairs, protocol_dunders, False, "defined"

    # scope == "all"
    pairs, exceeded = build_pairs(iter_names_all(), max_methods)
    if exceeded:
        # Guardrail: fall back to defined-only methods (plus __init__)
        protocol_dunders = []
        pairs, _ = build_pairs(iter_names_defined(), None)
        return pairs, protocol_dunders, True, "defined"

    return pairs, protocol_dunders, False, "all"


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
        return {"type": "class", "name": name, "module": module}

    # Fallback to string representation
    return {"type": "any", "raw": str(t)}


def _annotation_to_type_dict(annotation: Optional[str], default_module: Optional[str] = None) -> Dict[str, Any]:
    if not annotation:
        return {"type": "any"}

    try:
        node = ast.parse(annotation, mode="eval").body
        return _annotation_from_ast(node, default_module)
    except Exception:
        return {"type": "any", "raw": annotation}


def _annotation_from_ast(node: ast.AST, default_module: Optional[str]) -> Dict[str, Any]:
    if isinstance(node, ast.Name):
        name = node.id
        return _annotation_from_name(name, default_module)

    if isinstance(node, ast.Attribute):
        module = _attribute_to_str(node.value)
        name = node.attr
        if module == "typing":
            return _annotation_from_name(name, default_module)
        return {"type": "class", "name": name, "module": module}

    if isinstance(node, ast.Subscript):
        base = node.value
        base_name = _annotation_base_name(base)
        args = _annotation_slice_args(node.slice)

        if base_name in ("Optional", "typing.Optional"):
            inner = _annotation_from_ast(args[0], default_module) if args else {"type": "any"}
            return {"type": "optional", "inner_type": inner}

        if base_name in ("Union", "typing.Union"):
            types = [_annotation_from_ast(arg, default_module) for arg in args]
            return {"type": "union", "types": types}

        if base_name in ("List", "list", "typing.List"):
            element = _annotation_from_ast(args[0], default_module) if args else {"type": "any"}
            return {"type": "list", "element_type": element}

        if base_name in ("Dict", "dict", "typing.Dict"):
            key = _annotation_from_ast(args[0], default_module) if len(args) > 0 else {"type": "any"}
            value = _annotation_from_ast(args[1], default_module) if len(args) > 1 else {"type": "any"}
            return {"type": "dict", "key_type": key, "value_type": value}

        if base_name in ("Tuple", "tuple", "typing.Tuple"):
            if args:
                return {"type": "tuple", "element_types": [_annotation_from_ast(arg, default_module) for arg in args]}
            return {"type": "tuple"}

        if base_name in ("Set", "set", "typing.Set", "FrozenSet", "frozenset", "typing.FrozenSet"):
            element = _annotation_from_ast(args[0], default_module) if args else {"type": "any"}
            return {"type": "set", "element_type": element}

        return {"type": "generic", "origin": base_name, "args": [_annotation_from_ast(arg, default_module) for arg in args]}

    if isinstance(node, ast.Constant) and node.value is None:
        return {"type": "none"}

    return {"type": "any", "raw": ast.dump(node)}


def _annotation_from_name(name: str, default_module: Optional[str]) -> Dict[str, Any]:
    mapping = {
        "int": {"type": "int"},
        "float": {"type": "float"},
        "str": {"type": "string"},
        "bool": {"type": "boolean"},
        "bytes": {"type": "bytes"},
        "bytearray": {"type": "bytearray"},
        "list": {"type": "list"},
        "dict": {"type": "dict"},
        "tuple": {"type": "tuple"},
        "set": {"type": "set"},
        "frozenset": {"type": "frozenset"},
        "Any": {"type": "any"},
        "None": {"type": "none"},
        "NoneType": {"type": "none"},
    }

    if name in mapping:
        return mapping[name]

    return {"type": "class", "name": name, "module": default_module or ""}


def _attribute_to_str(node: ast.AST) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return _attribute_to_str(node.value) + "." + node.attr
    return ""


def _annotation_base_name(node: ast.AST) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return _attribute_to_str(node)
    return ""


def _annotation_slice_args(node: ast.AST) -> List[ast.AST]:
    if isinstance(node, ast.Tuple):
        return list(node.elts)
    if hasattr(ast, "Index") and isinstance(node, ast.Index):  # pragma: no cover
        return [_unwrap_index(node)]
    return [node]


def _unwrap_index(node: ast.Index) -> ast.AST:  # pragma: no cover
    return node.value


def _param_info(param: inspect.Parameter, type_hint: Any = None) -> Dict[str, Any]:
    info = {"name": param.name, "kind": param.kind.name}
    if param.default is not inspect.Parameter.empty:
        info["default"] = repr(param.default)
    if param.annotation is not inspect.Parameter.empty:
        info["annotation"] = _format_annotation(param.annotation)

    type_annotation = type_hint if type_hint is not None else param.annotation
    info["type"] = type_to_dict(type_annotation)
    return info


def _extract_docstring_from_body(body: List[Any]) -> Optional[str]:
    if not body or cst is None:
        return None
    first = body[0]
    if isinstance(first, cst.SimpleStatementLine) and first.body:
        expr = first.body[0]
        if isinstance(expr, cst.Expr) and isinstance(expr.value, cst.SimpleString):
            try:
                return expr.value.evaluated_value
            except Exception:
                return expr.value.value.strip("\"'")
    return None


def _parse_stub_file(path: str, module_name: str) -> Dict[str, Any]:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            source = handle.read()
    except Exception as exc:
        return {"error": f"stub_read_failed: {exc}"}

    if cst is None:
        return _parse_stub_ast(source, path, module_name)

    try:
        module = cst.parse_module(source)
    except Exception as exc:
        return {"error": f"stub_parse_failed: {exc}"}

    stub_info: Dict[str, Any] = {
        "path": path,
        "docstring": _extract_docstring_from_body(module.body),
        "functions": {},
        "classes": {},
    }

    for stmt in module.body:
        if isinstance(stmt, cst.FunctionDef):
            _collect_stub_function(stub_info, stmt, module, module_name)
        elif isinstance(stmt, cst.ClassDef):
            _collect_stub_class(stub_info, stmt, module, module_name)

    return stub_info


def _collect_stub_function(stub_info: Dict[str, Any], node: "cst.FunctionDef", module: "cst.Module", module_name: str) -> None:
    name = node.name.value
    func_info = _parse_stub_function(node, module, module_name)
    is_overload = _has_overload_decorator(node)

    entry = stub_info["functions"].setdefault(name, {"overloads": [], "impl": None})
    if is_overload:
        entry["overloads"].append(func_info)
    else:
        entry["impl"] = func_info


def _collect_stub_class(stub_info: Dict[str, Any], node: "cst.ClassDef", module: "cst.Module", module_name: str) -> None:
    name = node.name.value
    class_info = {
        "name": name,
        "docstring": _extract_docstring_from_body(node.body.body),
        "methods": {},
    }

    for stmt in node.body.body:
        if isinstance(stmt, cst.FunctionDef):
            method_info = _parse_stub_function(stmt, module, module_name, drop_first_param=True)
            is_overload = _has_overload_decorator(stmt)

            entry = class_info["methods"].setdefault(stmt.name.value, {"overloads": [], "impl": None})
            if is_overload:
                entry["overloads"].append(method_info)
            else:
                entry["impl"] = method_info

    stub_info["classes"][name] = class_info


def _parse_stub_ast(source: str, path: str, module_name: str) -> Dict[str, Any]:
    try:
        module = ast.parse(source)
    except Exception as exc:
        return {"error": f"stub_parse_failed: {exc}"}

    stub_info: Dict[str, Any] = {
        "path": path,
        "docstring": ast.get_docstring(module),
        "functions": {},
        "classes": {},
    }

    for stmt in module.body:
        if isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef)):
            _collect_stub_function_ast(stub_info, stmt, module_name)
        elif isinstance(stmt, ast.ClassDef):
            _collect_stub_class_ast(stub_info, stmt, module_name)

    return stub_info


def _collect_stub_function_ast(stub_info: Dict[str, Any], node: ast.AST, module_name: str) -> None:
    name = node.name
    func_info = _parse_stub_function_ast(node, module_name)
    is_overload = _ast_has_overload_decorator(node)

    entry = stub_info["functions"].setdefault(name, {"overloads": [], "impl": None})
    if is_overload:
        entry["overloads"].append(func_info)
    else:
        entry["impl"] = func_info


def _collect_stub_class_ast(stub_info: Dict[str, Any], node: ast.ClassDef, module_name: str) -> None:
    name = node.name
    class_info = {
        "name": name,
        "docstring": ast.get_docstring(node),
        "methods": {},
    }

    for stmt in node.body:
        if isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef)):
            method_info = _parse_stub_function_ast(stmt, module_name, drop_first_param=True)
            is_overload = _ast_has_overload_decorator(stmt)

            entry = class_info["methods"].setdefault(stmt.name, {"overloads": [], "impl": None})
            if is_overload:
                entry["overloads"].append(method_info)
            else:
                entry["impl"] = method_info

    stub_info["classes"][name] = class_info


def _parse_stub_function_ast(
    node: ast.AST,
    module_name: str,
    drop_first_param: bool = False,
) -> Dict[str, Any]:
    params = _parse_stub_params_ast(node.args, module_name)

    if drop_first_param and params:
        if params[0]["name"] in ("self", "cls"):
            params = params[1:]

    return_type = {"type": "any"}
    if node.returns is not None:
        annotation = _ast_to_source(node.returns)
        return_type = _annotation_to_type_dict(annotation, module_name)

    return {
        "name": node.name,
        "parameters": params,
        "return_type": return_type,
        "docstring": ast.get_docstring(node),
    }


def _parse_stub_params_ast(args: ast.arguments, module_name: str) -> List[Dict[str, Any]]:
    parsed: List[Dict[str, Any]] = []

    posonly = list(args.posonlyargs)
    regular = list(args.args)
    all_positional = posonly + regular
    defaults = list(args.defaults)
    default_offset = len(all_positional) - len(defaults)

    for idx, param in enumerate(all_positional):
        default = defaults[idx - default_offset] if idx >= default_offset else None
        kind = "POSITIONAL_ONLY" if idx < len(posonly) else "POSITIONAL_OR_KEYWORD"
        parsed.append(_stub_param_entry_ast(param, kind, module_name, default))

    if args.vararg:
        parsed.append(_stub_param_entry_ast(args.vararg, "VAR_POSITIONAL", module_name, None))

    for param, default in zip(args.kwonlyargs, args.kw_defaults):
        parsed.append(_stub_param_entry_ast(param, "KEYWORD_ONLY", module_name, default))

    if args.kwarg:
        parsed.append(_stub_param_entry_ast(args.kwarg, "VAR_KEYWORD", module_name, None))

    return parsed


def _stub_param_entry_ast(
    param: ast.arg,
    kind: str,
    module_name: str,
    default: Optional[ast.AST],
) -> Dict[str, Any]:
    annotation = _ast_to_source(param.annotation) if param.annotation is not None else None
    default_value = _ast_to_source(default) if default is not None else None

    entry = {
        "name": param.arg,
        "kind": kind,
        "annotation": annotation,
        "type": _annotation_to_type_dict(annotation, module_name),
    }
    if default_value is not None:
        entry["default"] = default_value
    return entry


def _ast_has_overload_decorator(node: ast.AST) -> bool:
    for decorator in getattr(node, "decorator_list", []):
        name = _ast_decorator_name(decorator)
        if name == "overload" or name.endswith(".overload"):
            return True
    return False


def _ast_decorator_name(node: ast.AST) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return _ast_decorator_name(node.value) + "." + node.attr
    if isinstance(node, ast.Call):
        return _ast_decorator_name(node.func)
    return ""


def _ast_to_source(node: Optional[ast.AST]) -> Optional[str]:
    if node is None:
        return None
    try:
        return ast.unparse(node)
    except Exception:
        return None


def _parse_stub_function(
    node: "cst.FunctionDef",
    module: "cst.Module",
    module_name: str,
    drop_first_param: bool = False,
) -> Dict[str, Any]:
    params = _parse_stub_params(node.params, module, module_name)

    if drop_first_param and params:
        if params[0]["name"] in ("self", "cls"):
            params = params[1:]

    return_type = {"type": "any"}
    if node.returns and node.returns.annotation:
        annotation = module.code_for_node(node.returns.annotation)
        return_type = _annotation_to_type_dict(annotation, module_name)

    return {
        "name": node.name.value,
        "parameters": params,
        "return_type": return_type,
        "docstring": _extract_docstring_from_body(node.body.body),
    }


def _parse_stub_params(params: "cst.Parameters", module: "cst.Module", module_name: str) -> List[Dict[str, Any]]:
    parsed: List[Dict[str, Any]] = []

    for param in params.posonly_params:
        parsed.append(_stub_param_entry(param, "POSITIONAL_ONLY", module, module_name))

    for param in params.params:
        parsed.append(_stub_param_entry(param, "POSITIONAL_OR_KEYWORD", module, module_name))

    if params.star_arg and isinstance(params.star_arg, cst.Param):
        parsed.append(_stub_param_entry(params.star_arg, "VAR_POSITIONAL", module, module_name))

    for param in params.kwonly_params:
        parsed.append(_stub_param_entry(param, "KEYWORD_ONLY", module, module_name))

    if params.star_kwarg:
        parsed.append(_stub_param_entry(params.star_kwarg, "VAR_KEYWORD", module, module_name))

    return parsed


def _stub_param_entry(param: "cst.Param", kind: str, module: "cst.Module", module_name: str) -> Dict[str, Any]:
    default = None
    if param.default is not None:
        default = module.code_for_node(param.default)

    annotation = None
    if param.annotation is not None:
        annotation = module.code_for_node(param.annotation.annotation)

    entry = {
        "name": param.name.value,
        "kind": kind,
        "annotation": annotation,
        "type": _annotation_to_type_dict(annotation, module_name),
    }
    if default is not None:
        entry["default"] = default
    return entry


def _has_overload_decorator(node: "cst.FunctionDef") -> bool:
    for decorator in node.decorators:
        name = _decorator_name(decorator.decorator)
        if name == "overload" or name.endswith(".overload"):
            return True
    return False


def _decorator_name(node: "cst.CSTNode") -> str:
    if isinstance(node, cst.Name):
        return node.value
    if isinstance(node, cst.Attribute):
        return _decorator_name(node.value) + "." + node.attr.value
    return ""


def _resolve_stub_for_module(module_name: str, config: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    cache_key = f"{module_name}:{json.dumps(config, sort_keys=True)}"
    if cache_key in _STUB_CACHE:
        return _STUB_CACHE[cache_key]

    stub_info = _discover_stub_for_module(module_name, config)
    _STUB_CACHE[cache_key] = stub_info
    return stub_info


def _discover_stub_for_module(module_name: str, config: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    candidates = _local_stub_candidates(module_name, config.get("stub_search_paths") or [])
    for path in candidates:
        if path and os.path.exists(path):
            info = _parse_stub_file(path, module_name)
            info["source"] = "local"
            return info

    types_pkg = _types_package_stub(module_name)
    if types_pkg:
        info = _parse_stub_file(types_pkg, module_name)
        info["source"] = "types-package"
        return info

    if config.get("use_typeshed") and config.get("typeshed_path"):
        typeshed_path = _typeshed_stub(module_name, config.get("typeshed_path"))
        if typeshed_path:
            info = _parse_stub_file(typeshed_path, module_name)
            info["source"] = "typeshed"
            return info

    return None


def _local_stub_candidates(module_name: str, extra_paths: List[str]) -> List[str]:
    paths: List[str] = []
    module_path = module_name.replace(".", os.sep)

    spec = None
    try:
        spec = importlib.util.find_spec(module_name)
    except Exception:
        spec = None

    if spec and spec.origin:
        if spec.origin.endswith((".py", ".pyc")):
            paths.append(spec.origin.rsplit(".", 1)[0] + ".pyi")

    if spec and spec.submodule_search_locations:
        for location in spec.submodule_search_locations:
            paths.append(os.path.join(location, "__init__.pyi"))

    for base in extra_paths:
        if not base:
            continue
        paths.append(os.path.join(base, module_path + ".pyi"))
        paths.append(os.path.join(base, module_path, "__init__.pyi"))

    return paths


def _types_package_stub(module_name: str) -> Optional[str]:
    root = module_name.split(".")[0]
    dist = None
    for dist_name in (f"types-{root.replace('_', '-')}", f"types-{root}"):
        try:
            dist = importlib_metadata.distribution(dist_name)
            if dist is not None:
                break
        except Exception:
            continue

    if dist is None:
        desired = _normalize_dist_name(f"types-{root}")
        for candidate in importlib_metadata.distributions():
            name = candidate.metadata.get("Name") if candidate.metadata else None
            if name and _normalize_dist_name(name) == desired:
                dist = candidate
                break

    if dist is None:
        return None

    rel_paths = _module_relative_paths(module_name)
    if dist.files:
        for file in dist.files:
            file_str = str(file)
            if any(file_str.endswith(rel_path) for rel_path in rel_paths):
                return str(dist.locate_file(file))
    else:
        base = str(dist.locate_file(""))
        for rel_path in rel_paths:
            candidate = os.path.join(base, rel_path)
            if os.path.exists(candidate):
                return candidate
    return None


def _typeshed_stub(module_name: str, typeshed_path: str) -> Optional[str]:
    root = module_name.split(".")[0]
    rel_paths = _module_relative_paths(module_name)

    stdlib_paths = [os.path.join(typeshed_path, "stdlib", rel_path) for rel_path in rel_paths]
    for path in stdlib_paths:
        if os.path.exists(path):
            return path

    third_party_root = os.path.join(typeshed_path, "stubs", root)
    for rel_path in rel_paths:
        candidate = os.path.join(third_party_root, rel_path)
        if os.path.exists(candidate):
            return candidate

    return None


def _module_relative_paths(module_name: str) -> List[str]:
    module_path = module_name.replace(".", os.sep)
    return [module_path + ".pyi", os.path.join(module_path, "__init__.pyi")]


def _normalize_dist_name(name: str) -> str:
    return name.lower().replace("-", "_")


def _stubgen_enabled(config: Dict[str, Any]) -> bool:
    stubgen = config.get("stubgen") or {}
    return bool(stubgen.get("enabled", True))


def _stubgen_cache_dir(config: Dict[str, Any]) -> str:
    stubgen = config.get("stubgen") or {}
    cache_dir = stubgen.get("cache_dir")
    if cache_dir:
        return str(cache_dir)
    return os.path.join(os.getcwd(), ".snakebridge", "stubgen_cache")


def _internal_stubgen(module_name: str) -> Optional[Dict[str, Any]]:
    try:
        module = importlib.import_module(module_name)
    except Exception:
        return None

    try:
        source = inspect.getsource(module)
    except Exception:
        return None

    info = _parse_stub_ast(source, f"<stubgen:{module_name}>", module_name)
    if info.get("error"):
        return None

    info["source"] = "stubgen"
    info["stubgen_output"] = "internal"
    return info


def _run_stubgen(module_name: str, config: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    if not _stubgen_enabled(config):
        return None

    cache_key = f"{module_name}:{json.dumps(config.get('stubgen') or {}, sort_keys=True)}"
    if cache_key in _STUBGEN_CACHE:
        return _STUBGEN_CACHE[cache_key]

    output_dir = _stubgen_cache_dir(config)
    os.makedirs(output_dir, exist_ok=True)

    stub_path = _find_stub_in_dir(module_name, output_dir)
    if stub_path and os.path.exists(stub_path):
        info = _parse_stub_file(stub_path, module_name)
        info["source"] = "stubgen"
        _STUBGEN_CACHE[cache_key] = info
        return info

    cmd = [
        sys.executable,
        "-m",
        "mypy.stubgen",
        "-m",
        module_name,
        "-o",
        output_dir,
        "--quiet",
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    except Exception as exc:
        info = _internal_stubgen(module_name)
        if info:
            info["stubgen_output"] = f"stubgen_failed: {exc}"
            _STUBGEN_CACHE[cache_key] = info
            return info

        info = {"error": f"stubgen_failed: {exc}"}
        _STUBGEN_CACHE[cache_key] = info
        return info

    stub_path = _find_stub_in_dir(module_name, output_dir)
    if stub_path and os.path.exists(stub_path):
        info = _parse_stub_file(stub_path, module_name)
        info["source"] = "stubgen"
        info["stubgen_output"] = result.stdout.strip() or result.stderr.strip()
        _STUBGEN_CACHE[cache_key] = info
        return info

    info = _internal_stubgen(module_name)
    if info:
        info["stubgen_output"] = result.stderr.strip() or result.stdout.strip()
        _STUBGEN_CACHE[cache_key] = info
        return info

    info = {"error": f"stubgen_failed: {result.stderr.strip() or result.stdout.strip()}"}
    _STUBGEN_CACHE[cache_key] = info
    return info


def _find_stub_in_dir(module_name: str, output_dir: str) -> Optional[str]:
    for rel_path in _module_relative_paths(module_name):
        candidate = os.path.join(output_dir, rel_path)
        if os.path.exists(candidate):
            return candidate
    return None


def _resolve_signature(
    name: str,
    obj: Optional[Any],
    module_name: str,
    config: Dict[str, Any],
    stub_info: Optional[Dict[str, Any]],
) -> Dict[str, Any]:
    sources = _normalize_signature_sources(config.get("signature_sources"))
    failures: List[str] = []
    fallback: Optional[Dict[str, Any]] = None
    fallback_has_types = False

    for source in sources:
        if source == "runtime":
            if obj is None:
                failures.append("runtime: missing object")
                continue
            result = _signature_from_runtime(obj)
            if result:
                result["signature_source"] = "runtime"
                result["signature_detail"] = "inspect.signature"
                result["signature_missing_reason"] = failures
                if _signature_has_type_info(result):
                    return result
                if fallback is None:
                    fallback = result
                    fallback_has_types = False
                failures.append("runtime: no type info")
                continue
            failures.append("runtime: signature unavailable")

        elif source == "text_signature":
            if obj is None:
                failures.append("text_signature: missing object")
                continue
            result = _signature_from_text_signature(obj)
            if result:
                result["signature_source"] = "text_signature"
                result["signature_detail"] = obj.__text_signature__
                result["signature_missing_reason"] = failures
                if _signature_has_type_info(result):
                    return result
                if fallback is None:
                    fallback = result
                    fallback_has_types = False
                failures.append("text_signature: no type info")
                continue
            failures.append("text_signature: unavailable")

        elif source == "runtime_hints":
            if obj is None:
                failures.append("runtime_hints: missing object")
                continue
            result = _signature_from_runtime_hints(obj, module_name)
            if result:
                result["signature_source"] = "runtime_hints"
                result["signature_detail"] = "annotations"
                result["signature_missing_reason"] = failures
                return result
            failures.append("runtime_hints: unavailable")

        elif source == "stub":
            result = _signature_from_stub(name, stub_info)
            if result:
                result["signature_source"] = "stub"
                result["signature_missing_reason"] = failures
                if fallback is None:
                    return result
                if not fallback_has_types and _signature_has_type_info(result):
                    return result
                failures.append("stub: no type info")
                continue
            failures.append("stub: not found")

        elif source == "stubgen":
            if fallback is not None:
                failures.append("stubgen: skipped (signature already found)")
                continue
            stubgen_info = _run_stubgen(module_name, config)
            result = _signature_from_stub(name, stubgen_info)
            if result:
                result["signature_source"] = "stubgen"
                result["signature_missing_reason"] = failures
                return result
            if stubgen_info and stubgen_info.get("error"):
                failures.append(f"stubgen: {stubgen_info.get('error')}")
            else:
                failures.append("stubgen: not found")

        elif source == "variadic":
            if fallback is not None:
                return fallback
            return {
                "parameters": [],
                "return_type": {"type": "any"},
                "signature_available": False,
                "signature_source": "variadic",
                "signature_detail": None,
                "signature_missing_reason": failures,
            }

    if fallback is not None:
        return fallback

    return {
        "parameters": [],
        "return_type": {"type": "any"},
        "signature_available": False,
        "signature_source": "variadic",
        "signature_detail": None,
        "signature_missing_reason": failures or ["no signature sources succeeded"],
    }


def _signature_has_type_info(signature: Optional[Dict[str, Any]]) -> bool:
    if not signature:
        return False

    if _type_is_specific(signature.get("return_type")):
        return True

    for param in signature.get("parameters", []):
        if _type_is_specific(param.get("type")):
            return True

    return False


def _type_is_specific(type_info: Optional[Dict[str, Any]]) -> bool:
    if not type_info:
        return False
    return type_info.get("type") not in (None, "any")


def _signature_from_runtime(obj: Any) -> Optional[Dict[str, Any]]:
    try:
        sig = inspect.signature(obj)
    except Exception:
        return None

    try:
        type_hints = typing.get_type_hints(obj)
    except Exception:
        type_hints = {}

    params = [_param_info(p, type_hints.get(p.name)) for p in sig.parameters.values()]
    return_type = type_to_dict(type_hints.get("return", sig.return_annotation))

    return {
        "parameters": params,
        "return_type": return_type,
        "signature_available": True,
    }


def _signature_from_text_signature(obj: Any) -> Optional[Dict[str, Any]]:
    text_sig = getattr(obj, "__text_signature__", None)
    if not text_sig:
        return None

    try:
        sig = inspect._signature_fromstr(inspect.Signature, obj, text_sig, False)
    except Exception:
        return None

    params = []
    for param in sig.parameters.values():
        entry = {
            "name": param.name,
            "kind": param.kind.name,
            "annotation": None,
            "type": {"type": "any"},
        }
        if param.default is not inspect.Parameter.empty:
            entry["default"] = repr(param.default)
        params.append(entry)

    return {
        "parameters": params,
        "return_type": {"type": "any"},
        "signature_available": True,
    }


def _signature_from_runtime_hints(obj: Any, module_name: str) -> Optional[Dict[str, Any]]:
    try:
        hints = typing.get_type_hints(obj)
    except Exception:
        hints = getattr(obj, "__annotations__", {}) or {}

    if not hints:
        return None

    params = []
    for name, hint in hints.items():
        if name == "return":
            continue
        params.append(
            {
                "name": name,
                "kind": "POSITIONAL_OR_KEYWORD",
                "annotation": _format_annotation(hint),
                "type": type_to_dict(hint),
            }
        )

    if not params:
        return None

    return_type = type_to_dict(hints.get("return"))
    return {
        "parameters": params,
        "return_type": return_type,
        "signature_available": True,
    }


def _signature_from_stub(name: str, stub_info: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    if not stub_info or stub_info.get("error"):
        return None

    function_entry = stub_info.get("functions", {}).get(name)
    if function_entry:
        chosen, overload_count = _choose_stub_signature(function_entry)
        if chosen:
            return {
                "parameters": chosen.get("parameters", []),
                "return_type": chosen.get("return_type", {"type": "any"}),
                "signature_available": True,
                "signature_detail": stub_info.get("path"),
                "overload_count": overload_count,
                "docstring": chosen.get("docstring"),
            }

    return None


def _choose_stub_signature(entry: Dict[str, Any]) -> Tuple[Optional[Dict[str, Any]], int]:
    overloads = entry.get("overloads") or []
    if overloads:
        chosen = max(overloads, key=lambda item: len(item.get("parameters") or []))
        return chosen, len(overloads)

    impl = entry.get("impl")
    if impl:
        return impl, 0

    return None, 0


def _signature_from_stub_method(
    class_name: str,
    method_name: str,
    stub_info: Optional[Dict[str, Any]],
) -> Optional[Dict[str, Any]]:
    if not stub_info or stub_info.get("error"):
        return None

    class_entry = stub_info.get("classes", {}).get(class_name)
    if not class_entry:
        return None

    method_entry = class_entry.get("methods", {}).get(method_name)
    if not method_entry:
        return None

    chosen, overload_count = _choose_stub_signature(method_entry)
    if not chosen:
        return None

    return {
        "parameters": chosen.get("parameters", []),
        "return_type": chosen.get("return_type", {"type": "any"}),
        "signature_available": True,
        "signature_detail": stub_info.get("path"),
        "overload_count": overload_count,
        "docstring": chosen.get("docstring"),
    }


def _stub_function_doc(name: str, stub_info: Optional[Dict[str, Any]]) -> Optional[str]:
    if not stub_info or stub_info.get("error"):
        return None
    entry = stub_info.get("functions", {}).get(name) or {}
    impl = entry.get("impl")
    if impl and impl.get("docstring"):
        return impl.get("docstring")
    for overload in entry.get("overloads") or []:
        if overload.get("docstring"):
            return overload.get("docstring")
    return None


def _stub_class_doc(name: str, stub_info: Optional[Dict[str, Any]]) -> Optional[str]:
    if not stub_info or stub_info.get("error"):
        return None
    entry = stub_info.get("classes", {}).get(name) or {}
    return entry.get("docstring")


def _stub_method_doc(
    class_name: str,
    method_name: str,
    stub_info: Optional[Dict[str, Any]],
) -> Optional[str]:
    if not stub_info or stub_info.get("error"):
        return None
    class_entry = stub_info.get("classes", {}).get(class_name) or {}
    method_entry = class_entry.get("methods", {}).get(method_name) or {}
    impl = method_entry.get("impl")
    if impl and impl.get("docstring"):
        return impl.get("docstring")
    for overload in method_entry.get("overloads") or []:
        if overload.get("docstring"):
            return overload.get("docstring")
    return None


def _resolve_docstring(obj: Optional[Any], stub_doc: Optional[str], module_doc: Optional[str]) -> Dict[str, Any]:
    runtime_doc = _docstring_text(obj) if obj is not None else ""
    if runtime_doc:
        return {"docstring": runtime_doc, "doc_source": "runtime", "doc_missing_reason": None}
    if stub_doc:
        return {"docstring": stub_doc, "doc_source": "stub", "doc_missing_reason": None}
    if module_doc:
        return {
            "docstring": module_doc,
            "doc_source": "module",
            "doc_missing_reason": "runtime docstring missing",
        }
    return {"docstring": "", "doc_source": "empty", "doc_missing_reason": "docstring missing"}


def _build_function_info(
    name: str,
    obj: Optional[Any],
    module_name: str,
    config: Dict[str, Any],
    stub_info: Optional[Dict[str, Any]],
    module_doc: Optional[str],
) -> Dict[str, Any]:
    signature = _resolve_signature(name, obj, module_name, config, stub_info)
    stub_doc = _stub_function_doc(name, stub_info)
    doc = _resolve_docstring(obj, stub_doc, module_doc)

    info = {
        "name": name,
        "type": "function",
        "callable": obj is not None and callable(obj),
        "module": module_name,
        "python_module": module_name,
        "parameters": signature.get("parameters", []),
        "return_type": signature.get("return_type", {"type": "any"}),
        "signature_available": signature.get("signature_available", False),
        "signature_source": signature.get("signature_source"),
        "signature_detail": signature.get("signature_detail"),
        "signature_missing_reason": signature.get("signature_missing_reason"),
        "overload_count": signature.get("overload_count"),
        "docstring": doc.get("docstring", ""),
        "doc_source": doc.get("doc_source"),
        "doc_missing_reason": doc.get("doc_missing_reason"),
    }

    return info


def _build_attribute_info(
    name: str,
    obj: Any,
    module_name: str,
    module_doc: Optional[str],
) -> Dict[str, Any]:
    doc = _resolve_docstring(obj, None, module_doc)
    return {
        "name": name,
        "type": "attribute",
        "module": module_name,
        "python_module": module_name,
        "signature_available": True,
        "signature_source": "runtime",
        "signature_detail": "attribute",
        "parameters": [],
        "return_type": type_to_dict(type(obj)),
        "docstring": doc.get("docstring", ""),
        "doc_source": doc.get("doc_source"),
        "doc_missing_reason": doc.get("doc_missing_reason"),
    }


def _build_class_info(
    name: str,
    cls: Optional[type],
    module_name: str,
    config: Dict[str, Any],
    stub_info: Optional[Dict[str, Any]],
    module_doc: Optional[str],
) -> Dict[str, Any]:
    class_stub_doc = _stub_class_doc(name, stub_info)
    doc = _resolve_docstring(cls, class_stub_doc, module_doc)

    methods: List[Dict[str, Any]] = []
    dunder_methods: List[str] = []
    methods_truncated = False
    effective_scope = None

    if cls is not None:
        scope = config.get("class_method_scope") or DEFAULT_CLASS_METHOD_SCOPE
        max_methods = config.get("max_class_methods")

        pairs, dunders, methods_truncated, effective_scope = _iter_class_method_pairs(
            cls, str(scope), max_methods
        )

        dunder_methods.extend(dunders)

        for method_name, method in pairs:

            method_stub = _signature_from_stub_method(name, method_name, stub_info)
            signature = _resolve_signature(method_name, method, module_name, config, stub_info)
            if method_stub and signature.get("signature_source") in ("variadic", "stubgen"):
                signature = method_stub
                signature["signature_source"] = "stub"

            stub_doc = _stub_method_doc(name, method_name, stub_info)
            doc_info = _resolve_docstring(method, stub_doc, module_doc)

            params = signature.get("parameters", [])
            params = _drop_self_param(params)

            methods.append({
                "name": method_name,
                "parameters": params,
                "docstring": doc_info.get("docstring", ""),
                "return_type": signature.get("return_type", {"type": "any"}),
                "signature_available": signature.get("signature_available", False),
                "signature_source": signature.get("signature_source"),
                "signature_detail": signature.get("signature_detail"),
                "signature_missing_reason": signature.get("signature_missing_reason"),
                "doc_source": doc_info.get("doc_source"),
                "doc_missing_reason": doc_info.get("doc_missing_reason"),
                "overload_count": signature.get("overload_count"),
            })
    else:
        class_entry = (stub_info or {}).get("classes", {}).get(name, {})
        for method_name in (class_entry.get("methods") or {}).keys():
            signature = _signature_from_stub_method(name, method_name, stub_info)
            stub_doc = _stub_method_doc(name, method_name, stub_info)
            doc_info = _resolve_docstring(None, stub_doc, module_doc)

            if signature:
                params = _drop_self_param(signature.get("parameters", []))
                methods.append({
                    "name": method_name,
                    "parameters": params,
                    "docstring": doc_info.get("docstring", ""),
                    "return_type": signature.get("return_type", {"type": "any"}),
                    "signature_available": signature.get("signature_available", False),
                    "signature_source": "stub",
                    "signature_detail": signature.get("signature_detail"),
                    "signature_missing_reason": signature.get("signature_missing_reason"),
                    "doc_source": doc_info.get("doc_source"),
                    "doc_missing_reason": doc_info.get("doc_missing_reason"),
                    "overload_count": signature.get("overload_count"),
                })

    attributes: List[str] = []
    if cls is not None:
        for attr_name, value in inspect.getmembers(cls):
            if attr_name.startswith("__"):
                continue
            if callable(value):
                continue
            attributes.append(attr_name)

    return {
        "name": name,
        "type": "class",
        "python_module": module_name,
        "docstring": doc.get("docstring", ""),
        "doc_source": doc.get("doc_source"),
        "doc_missing_reason": doc.get("doc_missing_reason"),
        "methods": methods,
        "attributes": attributes,
        "dunder_methods": dunder_methods,
        "methods_truncated": bool(methods_truncated),
        "method_scope": effective_scope or DEFAULT_CLASS_METHOD_SCOPE,
    }


def _drop_self_param(params: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    if params and params[0].get("name") in ("self", "cls"):
        return params[1:]
    return params


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


def introspect_symbols(
    module_name: str,
    symbols: List[str],
    config: Optional[Dict[str, Any]] = None,
) -> Union[List[Dict[str, Any]], Dict[str, Any]]:
    config = config or _parse_config(None)

    try:
        module = importlib.import_module(module_name)
    except Exception as exc:
        return {"error": f"Failed to import module '{module_name}': {exc}"}

    module_doc = inspect.getdoc(module) or ""

    stub_info = _resolve_stub_for_module(module_name, config)
    if stub_info and stub_info.get("docstring"):
        module_doc = stub_info.get("docstring") or module_doc

    results = []
    for name in symbols:
        obj = getattr(module, name, None)

        if obj is None:
            if stub_info and (name in stub_info.get("functions", {}) or name in stub_info.get("classes", {})):
                if name in stub_info.get("classes", {}):
                    results.append(_build_class_info(name, None, module_name, config, stub_info, module_doc))
                else:
                    results.append(_build_function_info(name, None, module_name, config, stub_info, module_doc))
                continue

            results.append({"name": name, "error": "not_found"})
            continue

        if inspect.isclass(obj):
            results.append(_build_class_info(name, obj, module_name, config, stub_info, module_doc))
        elif callable(obj):
            results.append(_build_function_info(name, obj, module_name, config, stub_info, module_doc))
        else:
            results.append(_build_attribute_info(name, obj, module_name, module_doc))
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


def introspect_module_namespace(module_name: str, namespace: str = "", config: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
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
    except Exception as e:
        # Catch all exceptions, not just ImportError - some modules fail with
        # AttributeError, RuntimeError, etc. during import (e.g., platform-specific code)
        return {"error": f"Failed to import module '{module_name}': {type(e).__name__}: {str(e)}"}

    namespace_info = {
        "functions": [],
        "classes": [],
        "attributes": []
    }

    config = config or _parse_config(None)
    stub_info = _resolve_stub_for_module(module_name, config)
    runtime_doc = inspect.getdoc(module) or ""
    module_doc = runtime_doc
    doc_source = "runtime" if runtime_doc else "empty"
    doc_missing_reason = None if runtime_doc else "docstring missing"

    if not module_doc and stub_info and stub_info.get("docstring"):
        module_doc = stub_info.get("docstring") or ""
        if module_doc:
            doc_source = "stub"
            doc_missing_reason = None

    if module_doc:
        namespace_info["docstring"] = module_doc
    namespace_info["doc_source"] = doc_source
    namespace_info["doc_missing_reason"] = doc_missing_reason

    # Get the module's __all__ if available (explicit public API)
    module_all = getattr(module, '__all__', None)

    seen_names = set()

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
            seen_names.add(name)
            if inspect.isclass(obj):
                class_info = _build_class_info(name, obj, module_name, config, stub_info, module_doc)
                namespace_info["classes"].append(class_info)
            elif inspect.isfunction(obj) or inspect.isbuiltin(obj) or (callable(obj) and not inspect.isclass(obj)):
                func_info = _build_function_info(name, obj, module_name, config, stub_info, module_doc)
                namespace_info["functions"].append(func_info)
            elif not inspect.ismodule(obj):
                attr_info = _build_attribute_info(name, obj, module_name, module_doc)
                namespace_info["attributes"].append(attr_info)
        except Exception as e:
            namespace_info.setdefault("issues", []).append(
                {"type": "introspect_member_failed", "member": name, "reason": str(e)}
            )
            continue

    # Handle lazy-loaded symbols from __all__ (for libraries that use __getattr__ for lazy imports)
    # These symbols are declared in __all__ but not visible to inspect.getmembers() until accessed
    if module_all is not None:
        for name in module_all:
            if name in seen_names:
                continue
            if name.startswith('_'):
                continue

            try:
                obj = getattr(module, name, None)
                if obj is None:
                    continue

                seen_names.add(name)
                if inspect.isclass(obj):
                    class_info = _build_class_info(name, obj, module_name, config, stub_info, module_doc)
                    namespace_info["classes"].append(class_info)
                elif inspect.isfunction(obj) or inspect.isbuiltin(obj) or (callable(obj) and not inspect.isclass(obj)):
                    func_info = _build_function_info(name, obj, module_name, config, stub_info, module_doc)
                    namespace_info["functions"].append(func_info)
                elif not inspect.ismodule(obj):
                    attr_info = _build_attribute_info(name, obj, module_name, module_doc)
                    namespace_info["attributes"].append(attr_info)
            except Exception as e:
                namespace_info.setdefault("issues", []).append(
                    {"type": "lazy_import_failed", "member": name, "reason": str(e)}
                )
                continue

    # Add stub-only symbols not present at runtime
    if stub_info:
        for name in stub_info.get("functions", {}).keys():
            if name in seen_names:
                continue
            if module_all is not None and name not in module_all:
                continue
            namespace_info["functions"].append(
                _build_function_info(name, None, module_name, config, stub_info, module_doc)
            )

        for name in stub_info.get("classes", {}).keys():
            if name in seen_names:
                continue
            if module_all is not None and name not in module_all:
                continue
            namespace_info["classes"].append(
                _build_class_info(name, None, module_name, config, stub_info, module_doc)
            )

    return namespace_info


def _discover_submodules(module_name: str) -> Tuple[List[str], List[Dict[str, Any]]]:
    issues: List[Dict[str, Any]] = []

    try:
        module = importlib.import_module(module_name)
    except Exception as exc:
        return [], [{"type": "import_error", "module": module_name, "reason": str(exc)}]

    if not hasattr(module, "__path__"):
        return [], []

    discovered: List[str] = []
    seen = set()

    for _finder, name, _is_pkg in pkgutil.walk_packages(module.__path__, prefix=module_name + "."):
        try:
            spec = importlib.util.find_spec(name)
        except Exception as exc:
            issues.append({"type": "submodule_spec_failed", "module": name, "reason": str(exc)})
            continue

        if spec is None:
            issues.append({"type": "submodule_spec_missing", "module": name})
            continue

        if not name.startswith(module_name + "."):
            continue

        relative = name[len(module_name) + 1 :]
        if relative and relative not in seen:
            discovered.append(relative)
            seen.add(relative)

    return discovered, issues


def _module_has_public_api(
    module_name: str,
    base_module: str,
    public_api_mode: str = "heuristic",
) -> bool:
    """
    Check if a module has a public API worth generating.

    A module has public API if:
    1. It's a PACKAGE (has __path__ - i.e., a directory), OR
    2. It declares __all__, OR
    3. It defines public functions/classes at the top level

    In "explicit_all" mode, packages/modules are included only when they define `__all__`.

    This uses static inspection (no import execution) so optional modules
    can still be included when they exist on disk but fail to import.

    Args:
        module_name: Full module name to check
        base_module: Base package name (e.g., "examplelib")

    Returns:
        True if module has public API worth generating
    """
    try:
        spec = importlib.util.find_spec(module_name)
    except Exception:
        spec = None

    if spec is None:
        return False

    explicit_all_only = public_api_mode in ("explicit_all", "explicit")

    if spec.submodule_search_locations:
        init_path = _package_init_path(spec)
        if explicit_all_only:
            return bool(init_path and _source_defines_all(init_path))

        # Heuristic mode: packages are always included (even empty __init__.py).
        if init_path and _source_has_public_api(init_path):
            return True
        return True

    origin = getattr(spec, "origin", None)
    if origin and os.path.exists(origin):
        if origin.endswith((".py", ".pyi")):
            if explicit_all_only:
                return _source_defines_all(origin)
            return _source_has_public_api(origin)
        return not explicit_all_only

    return False


def _package_init_path(spec: importlib.machinery.ModuleSpec) -> Optional[str]:
    origin = getattr(spec, "origin", None)
    if origin and origin.endswith("__init__.py"):
        return origin
    return None


def _source_defines_all(path: str) -> bool:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            source = handle.read()
    except Exception:
        return False

    try:
        tree = ast.parse(source)
    except Exception:
        return False

    for node in tree.body:
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for target in targets:
                if isinstance(target, ast.Name) and target.id == "__all__":
                    return True
        elif isinstance(node, ast.AugAssign):
            target = node.target
            if isinstance(target, ast.Name) and target.id == "__all__":
                return True

    return False


def _source_has_public_api(path: str) -> bool:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            source = handle.read()
    except Exception:
        return False

    try:
        tree = ast.parse(source)
    except Exception:
        return False

    has_all = False
    has_public_defs = False

    for node in tree.body:
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for target in targets:
                if isinstance(target, ast.Name) and target.id == "__all__":
                    has_all = True
                    break
        elif isinstance(node, ast.AugAssign):
            target = node.target
            if isinstance(target, ast.Name) and target.id == "__all__":
                has_all = True
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            if not node.name.startswith("_"):
                has_public_defs = True
        if has_all or has_public_defs:
            return True

    return False


def _parse_csv(value: Optional[str]) -> List[str]:
    if not value:
        return []
    return [part.strip() for part in value.split(",") if part.strip()]


def _is_pattern(value: str) -> bool:
    return any(ch in value for ch in ["*", "?", "["])


def _expand_patterns(patterns: List[str], candidates: List[str]) -> List[str]:
    if not patterns:
        return []

    matched: List[str] = []
    for pattern in patterns:
        if _is_pattern(pattern):
            matched.extend([item for item in candidates if fnmatch.fnmatchcase(item, pattern)])
        else:
            matched.append(pattern)
    return matched


def introspect_module(
    module_name: str,
    submodules: Optional[List[str]] = None,
    flat_mode: bool = False,
    config: Optional[Dict[str, Any]] = None,
    discover_submodules: bool = False,
    public_api: bool = False,
    exports_mode: bool = False,
    public_api_mode: str = "heuristic",
    module_include: Optional[List[str]] = None,
    module_exclude: Optional[List[str]] = None,
    module_depth: Optional[int] = None,
) -> Dict[str, Any]:
    """
    Introspect a Python module with optional submodule detection.

    Args:
        module_name: Name of the module to introspect
        submodules: List of submodule names to also introspect (e.g., ["linalg", "fft"])
        flat_mode: If True, use legacy flat format (v2.0), otherwise use namespaced format (v2.1)
        config: Introspection config dict
        discover_submodules: If True, walk packages to discover submodules automatically
        public_api: If True, only include modules with explicit public API (__all__ or defined-in-module)
        exports_mode: If True, derive submodules from explicit exports (root __all__) instead of walking
        public_api_mode: "heuristic" (default) or "explicit_all" (only modules/packages defining __all__)
        module_include: Submodules to force-include (relative to root)
        module_exclude: Submodules to exclude (relative to root)
        module_depth: Limit discovery depth (1 = direct children only)

    Returns:
        Dictionary with complete module information
    """
    config = config or _parse_config(None)
    issues: List[Dict[str, Any]] = []

    try:
        module = importlib.import_module(module_name)
    except ImportError as e:
        return {
            "error": f"Failed to import module '{module_name}': {str(e)}",
            "module": module_name
        }

    module_version = getattr(module, '__version__', None)
    runtime_doc = inspect.getdoc(module) or ""
    module_doc = runtime_doc
    doc_source = "runtime" if runtime_doc else "empty"
    doc_missing_reason = None if runtime_doc else "docstring missing"
    stub_info = _resolve_stub_for_module(module_name, config)
    if not module_doc and stub_info and stub_info.get("docstring"):
        module_doc = stub_info.get("docstring") or ""
        if module_doc:
            doc_source = "stub"
            doc_missing_reason = None
    module_file = module.__file__ if hasattr(module, '__file__') else None

    submodule_list: List[str] = [name for name in (submodules or []) if name]
    raw_candidates: List[str] = list(submodule_list)

    if exports_mode:
        module_all = getattr(module, "__all__", None)
        exported_modules: List[str] = []

        if module_all is None:
            issues.append(
                {
                    "type": "exports_mode_no_all",
                    "module": module_name,
                    "message": f"exports_mode enabled but {module_name} has no __all__; no submodules were auto-selected",
                }
            )
        else:
            for name in module_all:
                if not name or name.startswith("_"):
                    continue
                try:
                    obj = getattr(module, name, None)
                except Exception:
                    continue

                if obj is None:
                    continue

                if inspect.ismodule(obj):
                    obj_module_name = getattr(obj, "__name__", None)
                    if obj_module_name and obj_module_name.startswith(module_name + "."):
                        relative = obj_module_name[len(module_name) + 1 :]
                        if relative:
                            exported_modules.append(relative)

            if exported_modules:
                unique = sorted(set(exported_modules))
                for name in unique:
                    if name not in submodule_list:
                        submodule_list.append(name)

                issues.append(
                    {
                        "type": "exports_mode_modules",
                        "module": module_name,
                        "count": len(unique),
                        "message": f"exports_mode selected {len(unique)} exported submodule(s) from {module_name}.__all__",
                    }
                )

        raw_candidates = list(submodule_list)
    elif discover_submodules:
        discovered, discovery_issues = _discover_submodules(module_name)
        issues.extend(discovery_issues)
        for name in discovered:
            if name not in submodule_list:
                submodule_list.append(name)
        raw_candidates = list(submodule_list)

    # Filter to public API modules if requested
    if public_api and submodule_list:
        original_count = len(submodule_list)
        filtered_list = []
        for submodule in submodule_list:
            full_name = f"{module_name}.{submodule}"
            # Skip private modules (any path component starts with _)
            if any(part.startswith('_') for part in submodule.split('.')):
                continue
            # Check if module has public API
            if _module_has_public_api(full_name, module_name, public_api_mode):
                filtered_list.append(submodule)
        submodule_list = filtered_list
        # Record how many were filtered
        filtered_count = original_count - len(submodule_list)
        if filtered_count > 0:
            issues.append({
                "type": "public_api_filter",
                "filtered_count": filtered_count,
                "remaining_count": len(submodule_list),
                "message": f"Filtered {filtered_count} internal modules, {len(submodule_list)} public API modules remaining"
            })

    # Apply depth filter before excludes/includes
    if module_depth and module_depth > 0:
        submodule_list = [
            name for name in submodule_list if len(name.split(".")) <= module_depth
        ]

    # Apply exclude patterns
    exclude_list = _expand_patterns(module_exclude or [], raw_candidates)
    if exclude_list:
        exclude_set = set(exclude_list)
        submodule_list = [name for name in submodule_list if name not in exclude_set]

    # Apply include patterns last (explicit include overrides filters)
    include_list = _expand_patterns(module_include or [], raw_candidates)
    if include_list:
        include_set = set(include_list)
        for name in include_set:
            if name not in submodule_list:
                submodule_list.append(name)

    if flat_mode:
        module_info = {
            "module": module_name,
            "version": "2.0",
            "functions": [],
            "classes": [],
            "attributes": [],
            "issues": issues,
        }

        if module_doc:
            module_info["docstring"] = module_doc
        module_info["doc_source"] = doc_source
        module_info["doc_missing_reason"] = doc_missing_reason

        if module_version:
            module_info["module_version"] = module_version

        if module_file:
            module_info["file"] = module_file

        base_namespace = introspect_module_namespace(module_name, "", config)

        if base_namespace.get("error"):
            module_info["error"] = base_namespace.get("error")
            module_info["issues"].append({
                "type": "import_error",
                "module": module_name,
                "reason": base_namespace.get("error"),
            })
            return module_info

        module_info["functions"] = base_namespace.get("functions", [])
        module_info["classes"] = base_namespace.get("classes", [])
        module_info["attributes"] = base_namespace.get("attributes", [])

        if base_namespace.get("issues"):
            module_info["issues"].extend(base_namespace.get("issues") or [])

        return module_info

    module_info = {
        "module": module_name,
        "version": "2.1",
        "namespaces": {},
        "issues": issues,
    }

    if module_doc:
        module_info["docstring"] = module_doc
    module_info["doc_source"] = doc_source
    module_info["doc_missing_reason"] = doc_missing_reason

    if module_version:
        module_info["module_version"] = module_version

    if module_file:
        module_info["file"] = module_file

    base_namespace = introspect_module_namespace(module_name, "", config)
    if base_namespace:
        module_info["namespaces"][""] = base_namespace
        if base_namespace.get("error"):
            module_info["issues"].append({
                "type": "import_error",
                "module": module_name,
                "reason": base_namespace.get("error"),
            })

    for submodule in submodule_list:
        full_module_name = f"{module_name}.{submodule}"
        namespace_info = introspect_module_namespace(full_module_name, submodule, config)
        if namespace_info:
            module_info["namespaces"][submodule] = namespace_info
            if namespace_info.get("error"):
                module_info["issues"].append({
                    "type": "import_error",
                    "module": full_module_name,
                    "reason": namespace_info.get("error"),
                })

    return module_info


def introspect_module_docs(
    module_names: List[str],
    config: Optional[Dict[str, Any]] = None,
) -> List[Dict[str, Any]]:
    """
    Fetch docstrings for one or more modules without introspecting members.
    """
    config = config or _parse_config(None)
    results: List[Dict[str, Any]] = []

    for module_name in module_names:
        if not module_name:
            continue

        try:
            module = importlib.import_module(module_name)
        except ImportError as exc:
            results.append(
                {
                    "module": module_name,
                    "docstring": "",
                    "doc_source": "error",
                    "doc_missing_reason": f"Failed to import module '{module_name}': {str(exc)}",
                }
            )
            continue

        stub_info = _resolve_stub_for_module(module_name, config)
        module_doc = inspect.getdoc(module) or ""
        doc_source = "runtime" if module_doc else "empty"
        doc_missing_reason = None if module_doc else "docstring missing"

        if not module_doc and stub_info and stub_info.get("docstring"):
            module_doc = stub_info.get("docstring") or ""
            doc_source = "stub"
            doc_missing_reason = None

        info: Dict[str, Any] = {
            "module": module_name,
            "docstring": module_doc,
            "doc_source": doc_source,
            "doc_missing_reason": doc_missing_reason,
        }

        module_version = getattr(module, '__version__', None)
        if module_version:
            info["module_version"] = module_version

        results.append(info)

    return results


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
        '--module-docs',
        help='JSON array or comma-separated list of modules to fetch docstrings for',
        default=None
    )
    parser.add_argument(
        '--attribute',
        help='Single attribute name to introspect',
        default=None
    )
    parser.add_argument(
        '--config',
        help='JSON config for signature and stub resolution',
        default=None
    )
    parser.add_argument(
        '--discover-submodules',
        action='store_true',
        help='Discover submodules automatically when module is a package'
    )
    parser.add_argument(
        '--flat',
        action='store_true',
        help='Use legacy flat format (v2.0) instead of namespaced format (v2.1)'
    )
    parser.add_argument(
        '--public-api',
        action='store_true',
        help='Only include modules with explicit public API (__all__ or defined-in-module classes)'
    )
    parser.add_argument(
        '--exports-mode',
        action='store_true',
        help='Derive submodules from explicit exports (root __all__) instead of walking packages'
    )
    parser.add_argument(
        '--public-api-mode',
        choices=["heuristic", "explicit_all"],
        default="heuristic",
        help='When --public-api is set, controls how to detect public API modules'
    )
    parser.add_argument(
        '--module-include',
        help='Comma-separated list of submodules to force-include',
        default=None
    )
    parser.add_argument(
        '--module-exclude',
        help='Comma-separated list of submodules to exclude',
        default=None
    )
    parser.add_argument(
        '--module-depth',
        type=int,
        help='Limit submodule discovery depth (1 = direct children only)',
        default=None
    )

    args = parser.parse_args()

    module_name = args.module_flag or args.module
    if not module_name:
        parser.error("module name is required")
    submodules = args.submodules.split(',') if args.submodules else None
    module_include = _parse_csv(args.module_include)
    module_exclude = _parse_csv(args.module_exclude)
    module_depth = args.module_depth
    flat_mode = args.flat
    config = _parse_config(args.config)

    try:
        if args.attribute:
            result = introspect_attribute_info(module_name, args.attribute)
            print(json.dumps(result))
        elif args.module_docs:
            modules = _parse_symbols_arg(args.module_docs)
            result = introspect_module_docs(modules, config)
            print(json.dumps(result))
        elif args.symbols:
            symbols = _parse_symbols_arg(args.symbols)
            result = introspect_symbols(module_name, symbols, config)
            print(json.dumps(result))
        else:
            result = introspect_module(
                module_name,
                submodules=submodules,
                flat_mode=flat_mode,
                config=config,
                discover_submodules=args.discover_submodules,
                public_api=args.public_api,
                exports_mode=args.exports_mode,
                public_api_mode=args.public_api_mode,
                module_include=module_include,
                module_exclude=module_exclude,
                module_depth=module_depth,
            )
            print(json.dumps(result, indent=2))
    except Exception as e:
        error_type = type(e).__name__
        message = str(e)
        sys.stderr.write(f"{error_type}: {message}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
