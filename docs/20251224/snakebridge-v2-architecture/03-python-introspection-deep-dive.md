# Python Introspection Deep Dive for SnakeBridge v2

**Date**: 2024-12-24
**Author**: Research for SnakeBridge v2 Redesign
**Status**: Research Document

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Python's Inspect Module Capabilities](#pythons-inspect-module-capabilities)
3. [Type Hints and the Typing System](#type-hints-and-the-typing-system)
4. [Docstring Parsing Approaches](#docstring-parsing-approaches)
5. [Current SnakeBridge Implementation](#current-snakebridge-implementation)
6. [The Core Impedance Mismatch: Python Types → Elixir Types](#the-core-impedance-mismatch-python-types--elixir-types)
7. [Limitations and Edge Cases](#limitations-and-edge-cases)
8. [Recommendations for v2 Introspection Layer](#recommendations-for-v2-introspection-layer)

---

## Executive Summary

Python introspection is the cornerstone of SnakeBridge's ability to auto-generate Elixir adapters. The current implementation uses Python's `inspect` module and `typing.get_type_hints()` to extract:

- Function signatures with parameter metadata (names, kinds, defaults)
- Type annotations (when present)
- Docstrings
- Module structure (classes, methods, properties)

**Key Findings**:
- ✅ The current implementation successfully extracts basic signatures and docstrings
- ⚠️ Type hint extraction is basic and doesn't handle complex typing constructs (Generics, TypeVars, Protocols, Literal, etc.)
- ⚠️ Docstring parsing is non-existent (raw strings only, no structured parsing)
- ❌ No runtime type inference for untyped code
- ❌ The Python→Elixir type mapping is simplistic and falls back to `any` frequently

**The Central Challenge**: Python's gradual typing system (optional, expressive, runtime-flexible) vs Elixir's strict compile-time type system (required for Dialyzer, limited expressiveness) creates a fundamental impedance mismatch.

---

## Python's Inspect Module Capabilities

### Overview

The `inspect` module provides introspection capabilities for Python objects. It can examine:

- **Modules**: List members, check if it's a package, enumerate submodules
- **Classes**: List methods, properties, check inheritance
- **Functions/Methods**: Extract signatures, parameters, return annotations
- **Objects**: Determine types, check callability

### Core Functions Used in SnakeBridge

#### 1. `inspect.getmembers(object, predicate=None)`

Returns all members of an object as `(name, value)` pairs.

```python
# Current usage in adapter.py
for name, obj in inspect.getmembers(module, inspect.isfunction):
    # Process functions

for name, obj in inspect.getmembers(module, inspect.isclass):
    # Process classes
```

**Capabilities**:
- Filters by predicates: `isfunction`, `ismethod`, `isclass`, `ismodule`, `isbuiltin`, etc.
- Includes inherited members by default
- Can traverse entire object hierarchies

**Limitations**:
- Returns ALL members (including private, inherited, imported)
- Requires manual filtering for module-local vs imported items
- No indication of deprecation status

#### 2. `inspect.signature(callable)`

Returns a `Signature` object with parameter information.

```python
sig = inspect.signature(func)
for param_name, param in sig.parameters.items():
    print(f"Name: {param_name}")
    print(f"Kind: {param.kind}")  # POSITIONAL_ONLY, POSITIONAL_OR_KEYWORD, etc.
    print(f"Default: {param.default}")  # inspect.Parameter.empty if no default
    print(f"Annotation: {param.annotation}")  # inspect.Parameter.empty if no annotation
```

**Parameter Kinds** (critical for Elixir mapping):
- `POSITIONAL_ONLY`: Can only be passed positionally (e.g., `def f(a, /):`)
- `POSITIONAL_OR_KEYWORD`: Standard parameters (e.g., `def f(a, b):`)
- `VAR_POSITIONAL`: `*args`
- `KEYWORD_ONLY`: After `*` or `*args` (e.g., `def f(*, a):`)
- `VAR_KEYWORD`: `**kwargs`

**Current Implementation** (`_get_function_parameters` in adapter.py):
```python
def _get_function_parameters(self, func) -> list:
    try:
        sig = inspect.signature(func)
        params = []

        # Get type hints if available
        try:
            hints = get_type_hints(func)
        except Exception:
            hints = {}

        for param_name, param in sig.parameters.items():
            param_info = {
                "name": param_name,
                "required": param.default == inspect.Parameter.empty,
                "kind": str(param.kind.name).lower()
            }

            # Add default value if present
            if param.default != inspect.Parameter.empty:
                try:
                    param_info["default"] = repr(param.default)
                except Exception:
                    param_info["default"] = "..."

            # Add type hint if available
            if param_name in hints:
                param_info["type"] = self._type_to_string(hints[param_name])
            elif param.annotation != inspect.Parameter.empty:
                param_info["type"] = self._type_to_string(param.annotation)

            params.append(param_info)

        return params
    except (ValueError, TypeError):
        return []
```

**Strengths**:
- Captures all parameter metadata
- Handles defaults gracefully with `repr()`
- Falls back when type hints fail

**Weaknesses**:
- `_type_to_string()` is overly simplistic (see Type Hints section)
- No validation that `repr()` output is actually parseable
- No special handling for callbacks, descriptors, or complex defaults

#### 3. `inspect.getdoc(object)`

Returns the cleaned docstring (processed by `inspect.cleandoc`).

```python
docstring = inspect.getdoc(func)  # Removes indentation, strips leading/trailing whitespace
```

**Current Usage**: Raw docstrings are extracted but NOT parsed. This means:
- ❌ No structured parameter descriptions
- ❌ No return type documentation extraction
- ❌ No example code extraction
- ❌ No deprecation notice detection

#### 4. Module Introspection

**Submodule Discovery**:
```python
def _introspect_submodules(self, module, module_path: str) -> List[str]:
    submodules = []
    try:
        if hasattr(module, "__path__"):  # Is a package
            import pkgutil
            for importer, modname, ispkg in pkgutil.iter_modules(module.__path__):
                submodules.append(f"{module_path}.{modname}")
    except Exception as e:
        logger.debug(f"Could not enumerate submodules for {module_path}: {e}")
    return submodules
```

**Version Extraction**:
```python
version = getattr(module, "__version__", "unknown")
```

### Advanced Capabilities Not Currently Used

#### Source Code Access
```python
import inspect

# Get source file
inspect.getsourcefile(func)  # → "/path/to/file.py"

# Get source lines
inspect.getsourcelines(func)  # → (lines, line_number)

# Get entire source
inspect.getsource(func)  # → "def foo():\n    ..."
```

**Potential Use Cases**:
- Extracting inline comments for better documentation
- Detecting decorators for special handling
- Analyzing function complexity for stateless/stateful hints

#### AST-Based Introspection
```python
import ast

source = inspect.getsource(func)
tree = ast.parse(source)
# Analyze AST for:
# - Side effects (global/nonlocal usage)
# - I/O operations
# - Exception patterns
```

**Potential Use Cases**:
- Automatic purity detection (stateless vs stateful)
- Identifying functions that require special serialization

#### Runtime Type Checking
```python
import typing

# Check if object is instance of generic type
typing.get_origin(List[int])  # → list
typing.get_args(List[int])     # → (int,)
```

---

## Type Hints and the Typing System

### The Python Typing Landscape (PEPs)

Python's type system has evolved through multiple PEPs:

| PEP | Version | Features |
|-----|---------|----------|
| **PEP 484** | 3.5 (2015) | Type hints, `typing` module, `List`, `Dict`, `Optional`, `Union` |
| **PEP 526** | 3.6 (2016) | Variable annotations (`x: int = 5`) |
| **PEP 544** | 3.8 (2018) | Protocols (structural subtyping) |
| **PEP 585** | 3.9 (2020) | Generic built-ins (`list[int]` instead of `List[int]`) |
| **PEP 604** | 3.10 (2021) | Union operator (`int \| str` instead of `Union[int, str]`) |
| **PEP 612** | 3.10 (2021) | ParamSpec (for higher-order functions) |
| **PEP 646** | 3.11 (2022) | TypeVarTuple (variadic generics) |
| **PEP 673** | 3.11 (2022) | `Self` type |
| **PEP 692** | 3.12 (2023) | TypedDict with `**kwargs` |
| **PEP 698** | 3.12 (2023) | `@override` decorator |

### Current Type Extraction Implementation

#### `typing.get_type_hints()`

The current implementation uses `get_type_hints()` which resolves forward references and evaluates string annotations:

```python
from typing import get_type_hints

def _get_function_parameters(self, func) -> list:
    try:
        hints = get_type_hints(func)  # ← Resolves forward refs
    except Exception:
        hints = {}  # Fallback if type hints fail
```

**What it handles**:
- ✅ Resolves forward references (`"SomeClass"` → `SomeClass`)
- ✅ Evaluates `from __future__ import annotations`
- ✅ Returns a clean dict of `{param_name: type_object}`

**What it doesn't handle**:
- ❌ Fails silently on circular imports
- ❌ Fails on exotic types (TypeVars, ParamSpec, Concatenate)
- ❌ Doesn't provide context about type variance, bounds, or constraints

#### `_type_to_string()` - The Simplistic Type Stringifier

```python
def _type_to_string(self, type_hint) -> str:
    """Convert a type hint to a string representation."""
    if type_hint is None:
        return "None"

    # Handle typing module types
    origin = getattr(type_hint, "__origin__", None)
    if origin is not None:
        args = getattr(type_hint, "__args__", ())
        if args:
            args_str = ", ".join(self._type_to_string(a) for a in args)
            return f"{origin.__name__}[{args_str}]"
        return str(origin.__name__)

    # Handle regular types
    if hasattr(type_hint, "__name__"):
        return type_hint.__name__

    return str(type_hint)
```

**Critical Problems**:

1. **`__origin__` only exists on Generic types**:
   - Works: `List[int].__origin__` → `list`
   - Breaks: `int.__origin__` → `AttributeError`

2. **Union handling is broken**:
   ```python
   Union[int, str].__origin__  # → Union (not a class!)
   Union[int, str].__origin__.__name__  # → AttributeError
   ```

3. **Literal types ignored**:
   ```python
   Literal["a", "b", "c"]  # Collapses to "Literal"
   ```

4. **TypeVar, ParamSpec, Generic not handled**:
   ```python
   T = TypeVar('T')
   def f(x: T) -> T: ...
   # T is stringified as "~T" which is meaningless
   ```

5. **Callable signatures lost**:
   ```python
   Callable[[int, str], bool]  # Becomes "Callable[int, str, bool]"
   # Should be "function(int, str) :: boolean()" in Elixir
   ```

### Modern Type Constructs and How to Handle Them

#### 1. Generic Types (PEP 484, 585)

**Old Style (3.5-3.8)**:
```python
from typing import List, Dict, Set, Tuple

def process(items: List[int]) -> Dict[str, Set[int]]: ...
```

**New Style (3.9+)**:
```python
def process(items: list[int]) -> dict[str, set[int]]: ...
```

**Extraction**:
```python
import typing

def extract_generic_info(hint):
    origin = typing.get_origin(hint)  # list, dict, set, tuple, etc.
    args = typing.get_args(hint)      # (int,), (str, set[int]), etc.

    if origin is list:
        return {"kind": "list", "element_type": args[0] if args else Any}
    elif origin is dict:
        return {"kind": "dict", "key_type": args[0], "value_type": args[1]}
    # etc.
```

**Current Implementation**: ✅ Partially works but loses semantic information

**Recommended Fix**:
```python
def extract_type_descriptor(hint) -> dict:
    origin = typing.get_origin(hint)
    args = typing.get_args(hint)

    if origin is None:
        # Simple type
        if hint is type(None):
            return {"kind": "primitive", "primitive_type": "none"}
        elif isinstance(hint, type):
            return {"kind": "primitive", "primitive_type": hint.__name__}
        else:
            return {"kind": "any"}

    # Generic types
    if origin is list:
        return {
            "kind": "list",
            "element_type": extract_type_descriptor(args[0]) if args else {"kind": "any"}
        }
    elif origin is dict:
        return {
            "kind": "dict",
            "key_type": extract_type_descriptor(args[0]),
            "value_type": extract_type_descriptor(args[1])
        }
    elif origin is tuple:
        if args and args[-1] is Ellipsis:
            # Tuple[int, ...] - homogeneous
            return {
                "kind": "list",  # Map to Elixir list
                "element_type": extract_type_descriptor(args[0])
            }
        else:
            # Tuple[int, str, bool] - heterogeneous
            return {
                "kind": "tuple",
                "element_types": [extract_type_descriptor(a) for a in args]
            }
    # ... handle other origins
```

#### 2. Union Types (PEP 604)

**Old Style**:
```python
from typing import Union, Optional

def f(x: Union[int, str]) -> Optional[str]: ...
# Optional[str] is sugar for Union[str, None]
```

**New Style (3.10+)**:
```python
def f(x: int | str) -> str | None: ...
```

**Extraction**:
```python
import typing

def extract_union(hint):
    origin = typing.get_origin(hint)
    if origin is typing.Union:
        args = typing.get_args(hint)
        return {"kind": "union", "union_types": [extract_type_descriptor(a) for a in args]}
```

**Mapping to Elixir**:
```elixir
# Union[int, str] in Python
@spec function(integer() | String.t()) :: ...

# Optional[str] in Python (Union[str, None])
@spec function(String.t() | nil) :: ...
```

**Current Implementation**: ❌ Broken - `Union.__name__` doesn't exist

**Recommended Fix**: Handle Union specially in `extract_type_descriptor()` as shown above.

#### 3. Literal Types (PEP 586)

```python
from typing import Literal

def set_mode(mode: Literal["read", "write", "append"]) -> None: ...
```

**Current Behavior**: Collapses to `"Literal"` string

**Recommended Mapping**:
```elixir
# Option 1: Map to string union
@spec set_mode(String.t()) :: nil
# with guard: mode in ["read", "write", "append"]

# Option 2: Map to atom union (if values are valid atoms)
@spec set_mode(:read | :write | :append) :: nil
```

**Extraction**:
```python
if origin is Literal:
    values = typing.get_args(hint)
    return {
        "kind": "literal",
        "values": list(values),
        "base_type": type(values[0]).__name__ if values else "any"
    }
```

#### 4. Callable Types (PEP 484, 612)

```python
from typing import Callable

def apply(fn: Callable[[int, str], bool]) -> bool: ...
```

**Current Behavior**: Stringified to `"Callable[int, str, bool]"` (loses function semantics)

**Recommended Mapping**:
```elixir
@spec apply((integer(), String.t() -> boolean())) :: boolean()
```

**Extraction**:
```python
if origin is collections.abc.Callable:
    args = typing.get_args(hint)
    if len(args) == 2:
        param_types, return_type = args
        return {
            "kind": "callable",
            "param_types": [extract_type_descriptor(p) for p in param_types],
            "return_type": extract_type_descriptor(return_type)
        }
```

#### 5. TypeVar and Generics (PEP 484)

```python
from typing import TypeVar, Generic

T = TypeVar('T')
K = TypeVar('K')
V = TypeVar('V')

class Container(Generic[T]):
    def get(self) -> T: ...

def first(items: list[T]) -> T: ...
```

**Current Behavior**: TypeVars are stringified as `"~T"` which is meaningless

**The Problem**: Elixir doesn't have type variables in the same way. We need to either:

1. **Erase type variables** (map to `term()`)
   ```elixir
   @spec first([term()]) :: term()
   ```

2. **Use typespec variables** (limited support)
   ```elixir
   @spec first([t]) :: t when t: term()
   ```

3. **Generate multiple specs** (for bounded TypeVars)
   ```python
   T = TypeVar('T', int, str)  # T can only be int or str
   ```
   ```elixir
   @spec first([integer()]) :: integer()
   @spec first([String.t()]) :: String.t()
   ```

**Extraction**:
```python
from typing import TypeVar

if isinstance(hint, TypeVar):
    return {
        "kind": "typevar",
        "name": hint.__name__,
        "bound": extract_type_descriptor(hint.__bound__) if hint.__bound__ else None,
        "constraints": [extract_type_descriptor(c) for c in hint.__constraints__] if hint.__constraints__ else []
    }
```

#### 6. Protocols (PEP 544)

```python
from typing import Protocol

class Drawable(Protocol):
    def draw(self) -> None: ...

def render(obj: Drawable) -> None: ...
```

**Current Behavior**: Treated as a regular class

**The Problem**: Protocols are structural types (duck typing), not nominal types. Elixir has behaviours but they're nominal.

**Recommended Mapping**: Map to `term()` with a comment noting the expected protocol.

#### 7. Self Type (PEP 673)

```python
from typing import Self

class Builder:
    def add(self, x: int) -> Self: ...
```

**Current Behavior**: Stringified as `"Self"`

**Recommended Mapping**:
```elixir
@spec add(t(), integer()) :: t() when t: %Builder{}
# Or simply:
@spec add(t, integer()) :: t when t: %Builder{}
```

#### 8. Advanced: ParamSpec, TypeVarTuple (PEP 612, 646)

These are for higher-order functions and variadic generics. They're extremely rare in typical Python code.

**Recommendation**: Map to `term()` or `...` in v2.

---

## Docstring Parsing Approaches

### Current State: Raw Docstrings Only

The current implementation extracts docstrings but doesn't parse them:

```python
def _introspect_functions(self, module, module_path: str) -> dict:
    functions = {}
    for name, obj in inspect.getmembers(module, inspect.isfunction):
        functions[name] = {
            "name": name,
            "python_path": f"{module_path}.{name}",
            "docstring": inspect.getdoc(obj) or "",  # ← Raw string
            # ...
        }
```

**Result**: The manifest has truncated raw docstrings:
```json
{
  "name": "dumps",
  "doc": "Serialize ``obj`` to a JSON formatted ``str``.\n\nIf ``skipkeys`` is true then ``dict`` keys that are not basic types\n(``str``, ``int``, ``float``, ``bool``, ``None``) will be skipped\ninstead of raising"
}
```

### Docstring Conventions

Python has multiple docstring conventions:

#### 1. Google Style (Most Popular)

```python
def function(arg1: int, arg2: str) -> bool:
    """Summary line.

    Longer description explaining what this does.

    Args:
        arg1: Description of arg1.
        arg2: Description of arg2.

    Returns:
        Description of return value.

    Raises:
        ValueError: When something bad happens.

    Examples:
        >>> function(1, "test")
        True
    """
```

#### 2. NumPy Style (Scientific Computing)

```python
def function(arg1, arg2):
    """
    Summary line.

    Longer description.

    Parameters
    ----------
    arg1 : int
        Description of arg1.
    arg2 : str
        Description of arg2.

    Returns
    -------
    bool
        Description of return value.

    Examples
    --------
    >>> function(1, "test")
    True
    """
```

#### 3. reStructuredText (Sphinx)

```python
def function(arg1, arg2):
    """
    Summary line.

    :param arg1: Description of arg1.
    :type arg1: int
    :param arg2: Description of arg2.
    :type arg2: str
    :returns: Description of return value.
    :rtype: bool
    :raises ValueError: When something bad happens.

    Example::

        >>> function(1, "test")
        True
    """
```

### Parsing Libraries

#### 1. `docstring_parser` (Recommended)

```python
from docstring_parser import parse

docstring = parse(func.__doc__)

print(docstring.short_description)  # Summary
print(docstring.long_description)   # Detailed description

for param in docstring.params:
    print(f"{param.arg_name}: {param.type_name} - {param.description}")

if docstring.returns:
    print(f"Returns: {docstring.returns.type_name} - {docstring.returns.description}")

for raises in docstring.raises:
    print(f"Raises {raises.type_name}: {raises.description}")

for example in docstring.examples:
    print(f"Example: {example.description}")
```

**Supports**: Google, NumPy, reStructuredText styles
**Installation**: `pip install docstring-parser`

#### 2. `sphinx.ext.napoleon` (Google/NumPy → Sphinx)

Part of Sphinx, converts Google/NumPy styles to reStructuredText.

#### 3. `pydocstyle` (Linting Only)

Checks docstring compliance with PEP 257, but doesn't parse content.

### Recommended Docstring Strategy for v2

**Goal**: Extract structured information to enhance generated Elixir code.

**Approach**:

1. **Parse docstrings with `docstring_parser`**:
   ```python
   from docstring_parser import parse

   def extract_docstring_info(func):
       doc = parse(func.__doc__ or "")
       return {
           "summary": doc.short_description or "",
           "description": doc.long_description or "",
           "params": [
               {
                   "name": p.arg_name,
                   "type": p.type_name,
                   "description": p.description,
                   "optional": p.is_optional
               }
               for p in doc.params
           ],
           "returns": {
               "type": doc.returns.type_name if doc.returns else None,
               "description": doc.returns.description if doc.returns else None
           },
           "raises": [
               {"exception": r.type_name, "description": r.description}
               for r in doc.raises
           ],
           "examples": [e.description for e in doc.examples]
       }
   ```

2. **Use docstring types to augment missing type hints**:
   - If a parameter has no type annotation but docstring specifies type, use it
   - Validate consistency between annotations and docstrings

3. **Generate Elixir `@doc` with structured info**:
   ```elixir
   @doc """
   #{summary}

   #{description}

   ## Parameters
   #{for param in params, do: "- `#{param.name}`: #{param.description}"}

   ## Returns
   #{returns.description}

   ## Examples
   #{examples}
   """
   ```

4. **Detect deprecation warnings**:
   - Look for `.. deprecated::` in reStructuredText
   - Look for `Deprecated:` section in Google/NumPy
   - Add `@deprecated "..."` in Elixir

---

## Current SnakeBridge Implementation

### Architecture

```
Elixir Side:                          Python Side:
┌─────────────────────────┐           ┌──────────────────────────┐
│ SnakeBridge.Discovery   │           │ SnakeBridgeAdapter       │
│  └─ Introspector        │──gRPC────▶│  └─ describe_library()   │
│     └─ discover()       │           │     └─ _introspect_*()   │
└─────────────────────────┘           └──────────────────────────┘
         │                                       │
         │                                       │
         ▼                                       ▼
┌─────────────────────────┐           ┌──────────────────────────┐
│ Manifest (JSON)         │           │ Python inspect module    │
│  - functions[]          │           │  - signature()           │
│  - classes[]            │           │  - getmembers()          │
│  - types{}              │           │  - getdoc()              │
└─────────────────────────┘           │  - get_type_hints()      │
                                      └──────────────────────────┘
```

### Introspection Flow

1. **Elixir calls**: `SnakeBridge.Discovery.discover("numpy", depth: 2)`
2. **Introspector delegates** to Snakepit adapter via gRPC
3. **Python adapter** executes `describe_library("numpy", discovery_depth=2)`
4. **Adapter introspects**:
   - `importlib.import_module("numpy")`
   - `_introspect_functions()` → iterates `inspect.getmembers(module, inspect.isfunction)`
   - `_introspect_classes()` → iterates `inspect.getmembers(module, inspect.isclass)`
   - `_introspect_submodules()` → uses `pkgutil.iter_modules()`
5. **Returns schema**:
   ```json
   {
     "success": true,
     "library_version": "1.26.0",
     "functions": {...},
     "classes": {...},
     "submodules": [...],
     "type_hints": {...}
   }
   ```

### Key Implementation Files

#### `/priv/python/snakebridge_adapter/adapter.py`

**Main Methods**:

- `describe_library(module_path, discovery_depth)`: Entry point
- `_introspect_functions(module, module_path)`: Extract module-level functions
- `_introspect_classes(module, module_path, depth)`: Extract classes and methods
- `_introspect_submodules(module, module_path)`: Enumerate submodules
- `_extract_type_hints(module)`: Extract type annotations (currently unused)
- `_get_function_parameters(func)`: Extract parameter metadata
- `_get_return_type(func)`: Extract return type annotation
- `_type_to_string(type_hint)`: Convert type to string (broken for complex types)

**Strengths**:
- ✅ Handles depth limiting to prevent infinite recursion
- ✅ Filters out private members (`name.startswith("_")`)
- ✅ Filters out imported classes (checks `__module__` attribute)
- ✅ Graceful error handling with try/except blocks
- ✅ Captures parameter "kind" (positional_only, keyword_only, var_positional, var_keyword)

**Weaknesses**:
- ❌ `_type_to_string()` is too simplistic
- ❌ No docstring parsing
- ❌ No special handling for properties, descriptors, or metaclasses
- ❌ `_extract_type_hints()` is defined but never called
- ❌ No validation that introspected data is serializable
- ❌ No caching or memoization of expensive operations

#### `/lib/snakebridge/discovery/introspector.ex`

**Responsibilities**:
- Provides behaviour for introspection implementations
- Wraps Snakepit adapter calls
- Generates session IDs for introspection requests

**Weaknesses**:
- ❌ No retry logic for transient failures
- ❌ No timeout configuration
- ❌ No incremental/streaming introspection for large libraries

#### `/lib/snakebridge/type_system/mapper.ex`

**Responsibilities**:
- Normalizes Python type descriptors to consistent format
- Maps Python types to Elixir typespecs

**Type Mappings** (from code inspection):

| Python Type | Elixir Typespec | Notes |
|-------------|-----------------|-------|
| `int` | `integer()` | ✅ |
| `str` | `String.t()` | ✅ |
| `float` | `float()` | ✅ |
| `bool` | `boolean()` | ✅ |
| `bytes` | `binary()` | ✅ |
| `None` | `nil` | ✅ |
| `any` | `term()` | ✅ |
| `list` | `[element_type()]` | ✅ |
| `dict` | `%{optional(key_type) => value_type}` | ✅ |
| `tuple` | `{type1, type2, ...}` | ✅ Heterogeneous |
| `set` | `MapSet.t(element_type)` | ✅ |
| `datetime` | `DateTime.t()` | ✅ |
| `date` | `Date.t()` | ✅ |
| `time` | `Time.t()` | ✅ |
| `timedelta` | `integer()` | ⚠️ Lossy |
| `callable` | `(... -> term())` | ⚠️ Loses signature |
| `generator` | `Enumerable.t()` | ✅ |
| `union` | `type1 \| type2` | ✅ |
| `class` | `Module.t()` | ⚠️ Via `python_class_to_elixir_module()` |

**Strengths**:
- ✅ Handles both string and structured type descriptors
- ✅ Recursive normalization for nested types
- ✅ Smart capitalization for module names

**Weaknesses**:
- ❌ No handling for TypeVar, ParamSpec, Protocol, Literal
- ❌ `callable` mapping loses parameter types
- ❌ `timedelta` → `integer()` loses unit information
- ❌ No validation that generated Elixir types are syntactically valid

### Data Flow Example: `numpy.full()`

**Python Signature**:
```python
def full(
    shape: tuple[int, ...],
    fill_value: Any,
    dtype: DTypeLike | None = None,
    order: Literal['C', 'F'] = 'C',
    *,
    device: str | None = None,
    like: ArrayLike | None = None
) -> ndarray: ...
```

**Introspected Data** (from `numpy.json` manifest):
```json
{
  "name": "full",
  "params": [
    {"name": "shape", "required": true, "kind": "positional_or_keyword"},
    {"name": "fill_value", "required": true, "kind": "positional_or_keyword"},
    {"name": "dtype", "required": false, "kind": "positional_or_keyword", "default": "None"},
    {"name": "order", "required": false, "kind": "positional_or_keyword", "default": "'C'"},
    {"name": "device", "required": false, "kind": "keyword_only", "default": "None"},
    {"name": "like", "required": false, "kind": "keyword_only", "default": "None"}
  ],
  "returns": "any",
  "doc": "Return a new array of given shape and type, filled with `fill_value`..."
}
```

**Problems**:
- ❌ No type information for any parameter
- ❌ Return type is `"any"` instead of `ndarray`
- ❌ `Literal['C', 'F']` constraint lost
- ❌ Keyword-only parameters are captured but not validated

---

## The Core Impedance Mismatch: Python Types → Elixir Types

### Philosophical Differences

| Aspect | Python | Elixir |
|--------|--------|--------|
| **Typing** | Gradual (optional, runtime) | Strong (compile-time, required for Dialyzer) |
| **Type System** | Nominal + Structural (Protocols) | Nominal only |
| **Generics** | Full support (TypeVar, ParamSpec, etc.) | Limited (no higher-kinded types) |
| **Type Inference** | None (mypy/pyright are external tools) | Limited (Dialyzer infers types) |
| **Refinement Types** | Limited (Literal, TypeGuard) | Limited (guards in specs) |
| **Variance** | Explicit (covariant, contravariant, invariant) | No explicit variance |
| **Subtyping** | Structural (Protocols) + Nominal (classes) | Nominal only |
| **Null Safety** | Optional (via Union with None) | Explicit (nil is a value) |

### The Central Problem: What to do with `any`/`term()`?

Current behavior: When type information is missing or too complex, fall back to `any` → `term()`.

**Consequences**:
- ✅ Safe: `term()` accepts anything
- ❌ Useless for Dialyzer: No static checking
- ❌ Poor developer experience: No autocomplete, no type hints

**Example**: `numpy.full()`
```python
# Python (actual types)
def full(
    shape: tuple[int, ...],
    fill_value: Any,
    dtype: np.dtype | None = None,
    # ...
) -> np.ndarray: ...
```

```elixir
# Current generated Elixir
@spec full(term(), term(), term(), term(), term(), term()) :: term()

# Desired Elixir (manual)
@spec full(
  shape :: tuple() | [integer()],
  fill_value :: term(),
  dtype :: term(),
  order :: String.t(),
  device :: String.t() | nil,
  like :: term()
) :: term()  # ndarray is opaque anyway
```

### Specific Mapping Challenges

#### 1. TypeVar: No Direct Equivalent

**Python**:
```python
T = TypeVar('T')
def identity(x: T) -> T: ...
```

**Elixir Options**:

**Option A: Erase to `term()`**
```elixir
@spec identity(term()) :: term()
```
❌ Loses type relationship

**Option B: Use typespec variable**
```elixir
@spec identity(t) :: t when t: term()
```
✅ Preserves relationship
⚠️ Dialyzer doesn't really use this

**Option C: Generate multiple specs for bounded TypeVars**
```python
T = TypeVar('T', int, str)
def f(x: T) -> T: ...
```
```elixir
@spec f(integer()) :: integer()
@spec f(String.t()) :: String.t()
```
✅ Precise
❌ Only works for constrained TypeVars

#### 2. Literal: No Direct Equivalent

**Python**:
```python
def open(mode: Literal["r", "w", "a"]) -> File: ...
```

**Elixir Options**:

**Option A: String type with comment**
```elixir
@spec open(mode :: String.t()) :: term()
# mode must be one of: "r", "w", "a"
```

**Option B: Atom union** (if values are valid atoms)
```elixir
@spec open(mode :: :r | :w | :a) :: term()
```
✅ Type-safe
❌ Requires runtime conversion in bridge code

**Option C: Custom type**
```elixir
@type file_mode :: :read | :write | :append
@spec open(file_mode()) :: term()
```
✅ Most idiomatic
❌ Requires maintaining custom type definitions

#### 3. Union: Directly Supported but with Caveats

**Python**:
```python
def f(x: int | str | None) -> bool: ...
```

**Elixir**:
```elixir
@spec f(integer() | String.t() | nil) :: boolean()
```
✅ Direct mapping

**BUT**: Union explosion problem
```python
def complex_func(
    a: int | str,
    b: float | bool,
    c: list[int] | dict[str, int] | None
) -> tuple[int, ...] | list[str] | None: ...
```
Each parameter has 2-3 options = combinatorial explosion in Dialyzer analysis.

**Mitigation**: Use `term()` for parameters with >3 union members.

#### 4. Callable: Partial Support

**Python**:
```python
def apply(fn: Callable[[int, str], bool]) -> bool: ...
```

**Elixir**:
```elixir
@spec apply((integer(), String.t() -> boolean())) :: boolean()
```
✅ Supported
⚠️ Elixir function types have limited expressiveness

**Python**:
```python
def higher_order(
    fn: Callable[..., T],  # Variadic
    *args: Any
) -> T: ...
```

**Elixir**:
```elixir
@spec higher_order((... -> t), [term()]) :: t when t: term()
```
⚠️ `...` in function type means "any arity"
❌ Can't express "at least N arguments"

#### 5. Protocol: No Direct Mapping

**Python**:
```python
class Drawable(Protocol):
    def draw(self) -> None: ...

def render(obj: Drawable) -> None: ...
```

**Elixir** has behaviours but they're nominal:
```elixir
defmodule Drawable do
  @callback draw() :: :ok
end

@spec render(module()) :: :ok  # ← Expects module name, not instance
```

**Problem**: Python Protocols are structural (instance-based), Elixir behaviours are nominal (module-based).

**Workaround**: Map `Protocol` types to `term()` with documentation comment.

#### 6. Generic Classes: Limited Support

**Python**:
```python
class Container(Generic[T]):
    def get(self) -> T: ...
    def set(self, item: T) -> None: ...

container: Container[int] = Container()
```

**Elixir**: No parameterized types for structs
```elixir
defmodule Container do
  @type t :: %Container{}  # ← Can't parameterize

  @spec get(t()) :: term()  # ← Lost the type parameter
  @spec set(t(), term()) :: :ok
end
```

**Workaround**: Either:
1. Generate separate modules for common instantiations (e.g., `Container.Integer`, `Container.String`)
2. Use `term()` and document the expected type

#### 7. Complex Nested Types

**Python**:
```python
def process(
    data: dict[str, list[tuple[int, Optional[str]]]]
) -> list[dict[str, Any]]: ...
```

**Elixir**:
```elixir
@spec process(%{
  optional(String.t()) => [{integer(), String.t() | nil}]
}) :: [%{optional(String.t()) => term()}]
```
✅ Fully expressible
⚠️ Complex specs are hard to read and maintain

**Recommendation**: For deeply nested types (>3 levels), introduce type aliases:
```elixir
@type data_point :: {integer(), String.t() | nil}
@type data_list :: [data_point()]
@type data_map :: %{optional(String.t()) => data_list()}

@spec process(data_map()) :: [%{optional(String.t()) => term()}]
```

---

## Limitations and Edge Cases

### 1. Introspection Failures

**Built-in Functions** (C extensions):
```python
import math
inspect.signature(math.sqrt)  # ✅ Works in Python 3.3+
```

**Cython/Numba/Extension Modules**:
```python
import some_cython_module
inspect.signature(some_cython_module.fast_function)  # ❌ May fail
```

**Workaround**: Maintain manual type stubs for popular C extension libraries.

### 2. Dynamic Code

**`exec()`/`eval()` functions**:
```python
def dynamic_function():
    exec("def generated(): pass")
    return generated  # Can't introspect
```

**Metaclasses and Descriptors**:
```python
class Meta(type):
    def __new__(mcs, name, bases, namespace):
        # Dynamically add methods
        namespace['auto_generated'] = lambda self: None
        return super().__new__(mcs, name, bases, namespace)

class MyClass(metaclass=Meta):
    pass

inspect.getmembers(MyClass)  # ← Shows auto_generated, but where did it come from?
```

**Workaround**: Document that SnakeBridge only introspects statically-defined code.

### 3. Forward References and Circular Imports

```python
# module_a.py
from module_b import B

class A:
    def use_b(self) -> B: ...  # Circular import

# module_b.py
from module_a import A

class B:
    def use_a(self) -> A: ...
```

**Problem**: `get_type_hints()` resolves forward references by importing, causing circular import errors.

**Workaround**:
```python
# Use string annotations
class A:
    def use_b(self) -> "B": ...  # Forward reference as string
```

**SnakeBridge Behavior**: Currently catches exceptions from `get_type_hints()` and falls back to empty dict.

**Recommendation**: Use AST parsing as fallback:
```python
import ast

def parse_annotation_string(annotation_str: str) -> str:
    """Parse string annotation without importing."""
    try:
        tree = ast.parse(annotation_str, mode='eval')
        return ast.unparse(tree)
    except:
        return "term"
```

### 4. Runtime-Only Type Information

Some libraries use runtime type checking (e.g., Pydantic, dataclasses):

```python
from pydantic import BaseModel

class User(BaseModel):
    name: str
    age: int
```

`User.__annotations__` exists, but `inspect.signature(User.__init__)` shows auto-generated parameters.

**Workaround**: Special handling for known frameworks:
```python
def introspect_pydantic_model(cls):
    if issubclass(cls, BaseModel):
        return {
            field_name: {
                "type": field.type_,
                "required": field.required,
                "default": field.default
            }
            for field_name, field in cls.__fields__.items()
        }
```

### 5. Overloads (PEP 484)

```python
from typing import overload

@overload
def process(data: int) -> str: ...

@overload
def process(data: str) -> int: ...

def process(data):
    if isinstance(data, int):
        return str(data)
    return int(data)
```

**Problem**: `inspect.signature()` only sees the implementation (no type hints).

**Solution**: Use `typing.get_overloads()` (Python 3.11+):
```python
from typing import get_overloads

overloads = get_overloads(process)
for overload_func in overloads:
    sig = inspect.signature(overload_func)
    # Extract each overload signature
```

**Elixir Mapping**: Generate multiple `@spec`:
```elixir
@spec process(integer()) :: String.t()
@spec process(String.t()) :: integer()
```

### 6. Deprecated and Private APIs

**Problem**: Introspection shows ALL members, including deprecated and private APIs.

**Detection Strategies**:

1. **Name-based** (current):
   ```python
   if name.startswith("_"):
       continue  # Skip private
   ```

2. **Decorator-based**:
   ```python
   import warnings

   def is_deprecated(func):
       # Check for deprecation warnings in wrapper
       return any(
           isinstance(w, DeprecationWarning)
           for w in warnings.filters
       )
   ```

3. **Docstring-based**:
   ```python
   def is_deprecated(func):
       doc = inspect.getdoc(func) or ""
       return "deprecated" in doc.lower() or ".. deprecated::" in doc
   ```

**Recommendation**: Combine all three approaches and mark deprecated functions in manifest:
```json
{
  "name": "old_function",
  "deprecated": true,
  "deprecation_message": "Use new_function instead. Will be removed in v2.0."
}
```

### 7. Module-Level Constants and Enums

```python
import enum

class Color(enum.Enum):
    RED = 1
    GREEN = 2
    BLUE = 3

MAX_SIZE = 1024
```

**Current Behavior**: Not introspected.

**Recommendation**: Add constants extraction:
```python
def _introspect_constants(self, module):
    constants = {}
    for name, obj in inspect.getmembers(module):
        if name.isupper() and not inspect.isclass(obj) and not inspect.isfunction(obj):
            constants[name] = {
                "name": name,
                "value": repr(obj),
                "type": type(obj).__name__
            }
    return constants

def _introspect_enums(self, module):
    enums = {}
    for name, obj in inspect.getmembers(module, lambda x: isinstance(x, type) and issubclass(x, enum.Enum)):
        enums[name] = {
            "name": name,
            "members": {m.name: m.value for m in obj}
        }
    return enums
```

**Elixir Mapping**:
```elixir
# Constants as module attributes
@max_size 1024

# Enums as atoms
@type color :: :red | :green | :blue
```

### 8. Properties and Descriptors

```python
class Example:
    @property
    def value(self) -> int:
        return self._value

    @value.setter
    def value(self, v: int):
        self._value = v
```

**Current Behavior**: Properties are captured but not distinguished from regular attributes.

**Recommendation**:
```python
def _get_class_properties(self, cls) -> list:
    properties = []
    for name, obj in inspect.getmembers(cls):
        if isinstance(obj, property):
            properties.append({
                "name": name,
                "readonly": obj.fset is None,
                "getter_type": self._get_return_type(obj.fget) if obj.fget else None,
                "setter_type": self._get_function_parameters(obj.fset)[0]["type"] if obj.fset else None
            })
    return properties
```

**Elixir Mapping**: Generate getter/setter functions:
```elixir
@spec value(t()) :: integer()  # getter
@spec value(t(), integer()) :: t()  # setter (returns modified instance)
```

---

## Recommendations for v2 Introspection Layer

### 1. Enhanced Type Extraction

**Goal**: Extract richer type information to generate better Elixir specs.

**Implementation**:

```python
import typing
from typing import get_origin, get_args, get_type_hints

def extract_type_descriptor(hint) -> dict:
    """
    Convert Python type hint to structured descriptor.

    Returns a dict with:
    - kind: "primitive" | "list" | "dict" | "tuple" | "union" | "callable" | "typevar" | "literal" | "class" | "any"
    - Additional fields based on kind
    """
    # Handle None
    if hint is type(None) or hint is None:
        return {"kind": "primitive", "primitive_type": "none"}

    # Get origin and args
    origin = get_origin(hint)
    args = get_args(hint)

    # No origin = simple type
    if origin is None:
        if isinstance(hint, type):
            # Built-in type or class
            if hint in (int, str, float, bool, bytes):
                return {"kind": "primitive", "primitive_type": hint.__name__}
            else:
                return {"kind": "class", "class_path": f"{hint.__module__}.{hint.__name__}"}
        elif isinstance(hint, typing.TypeVar):
            # TypeVar
            return {
                "kind": "typevar",
                "name": hint.__name__,
                "bound": extract_type_descriptor(hint.__bound__) if hint.__bound__ else None,
                "constraints": [extract_type_descriptor(c) for c in hint.__constraints__]
            }
        else:
            return {"kind": "any"}

    # Generic types
    if origin is list:
        return {
            "kind": "list",
            "element_type": extract_type_descriptor(args[0]) if args else {"kind": "any"}
        }
    elif origin is dict:
        return {
            "kind": "dict",
            "key_type": extract_type_descriptor(args[0]) if len(args) > 0 else {"kind": "any"},
            "value_type": extract_type_descriptor(args[1]) if len(args) > 1 else {"kind": "any"}
        }
    elif origin is tuple:
        if args and args[-1] is Ellipsis:
            # Variable-length tuple (homogeneous)
            return {
                "kind": "list",  # Map to list in Elixir
                "element_type": extract_type_descriptor(args[0]) if len(args) > 1 else {"kind": "any"}
            }
        else:
            # Fixed-length tuple (heterogeneous)
            return {
                "kind": "tuple",
                "element_types": [extract_type_descriptor(a) for a in args]
            }
    elif origin is set:
        return {
            "kind": "set",
            "element_type": extract_type_descriptor(args[0]) if args else {"kind": "any"}
        }
    elif origin is typing.Union:
        # Union type
        return {
            "kind": "union",
            "union_types": [extract_type_descriptor(a) for a in args]
        }
    elif origin is typing.Literal:
        # Literal type
        return {
            "kind": "literal",
            "values": list(args),
            "base_type": type(args[0]).__name__ if args else "any"
        }
    elif origin in (collections.abc.Callable, typing.Callable):
        # Callable type
        if len(args) >= 2:
            *param_types, return_type = args
            return {
                "kind": "callable",
                "param_types": [extract_type_descriptor(p) for p in param_types[0]] if param_types and param_types[0] is not Ellipsis else [],
                "return_type": extract_type_descriptor(return_type),
                "variadic": param_types and param_types[0] is Ellipsis
            }
        else:
            return {"kind": "callable", "param_types": [], "return_type": {"kind": "any"}, "variadic": True}
    else:
        # Unknown generic type
        return {"kind": "class", "class_path": str(origin)}
```

**Usage**:
```python
def _get_function_parameters(self, func) -> list:
    try:
        sig = inspect.signature(func)
        hints = get_type_hints(func)

        params = []
        for param_name, param in sig.parameters.items():
            param_info = {
                "name": param_name,
                "required": param.default == inspect.Parameter.empty,
                "kind": str(param.kind.name).lower()
            }

            # Add default value
            if param.default != inspect.Parameter.empty:
                param_info["default"] = repr(param.default)

            # Add type descriptor
            type_hint = hints.get(param_name, param.annotation)
            if type_hint != inspect.Parameter.empty:
                param_info["type_descriptor"] = extract_type_descriptor(type_hint)

            params.append(param_info)

        return params
    except Exception:
        return []
```

### 2. Docstring Parsing Integration

**Goal**: Extract structured information from docstrings to augment type hints and generate better documentation.

**Implementation**:

```python
from docstring_parser import parse

def _introspect_function_enhanced(self, func, module_path: str) -> dict:
    """Enhanced function introspection with docstring parsing."""

    # Basic introspection
    name = func.__name__
    doc_raw = inspect.getdoc(func) or ""
    doc_parsed = parse(doc_raw)

    # Parameters from signature
    params = self._get_function_parameters(func)

    # Augment with docstring info
    for param in params:
        doc_param = next((p for p in doc_parsed.params if p.arg_name == param["name"]), None)
        if doc_param:
            param["description"] = doc_param.description
            # Use docstring type if annotation is missing
            if "type_descriptor" not in param and doc_param.type_name:
                param["type_descriptor"] = {"kind": "any"}  # Fallback for string types
                param["type_string"] = doc_param.type_name

    # Return type
    return_type = self._get_return_type(func)
    return_desc = doc_parsed.returns.description if doc_parsed.returns else None

    # Detect deprecation
    deprecated = "deprecated" in doc_raw.lower()
    deprecation_msg = None
    if deprecated:
        # Try to extract deprecation message
        import re
        match = re.search(r'deprecated:?\s*(.+)', doc_raw, re.IGNORECASE)
        if match:
            deprecation_msg = match.group(1).strip()

    return {
        "name": name,
        "python_path": f"{module_path}.{name}",
        "params": params,
        "return_type": return_type,
        "return_description": return_desc,
        "summary": doc_parsed.short_description or "",
        "description": doc_parsed.long_description or "",
        "deprecated": deprecated,
        "deprecation_message": deprecation_msg,
        "examples": [e.description for e in doc_parsed.examples] if doc_parsed.examples else []
    }
```

### 3. Improved Elixir Type Mapping

**Goal**: Generate idiomatic Elixir typespecs from Python type descriptors.

**Implementation** (in Elixir's `TypeSystem.Mapper`):

```elixir
defmodule SnakeBridge.TypeSystem.Mapper.V2 do
  @moduledoc """
  Enhanced type mapping for v2 with support for complex Python types.
  """

  def to_elixir_spec(descriptor) when is_map(descriptor) do
    case descriptor do
      %{"kind" => "primitive", "primitive_type" => ptype} ->
        map_primitive(ptype)

      %{"kind" => "list", "element_type" => elem} ->
        inner = to_elixir_spec(elem)
        quote do: [unquote(inner)]

      %{"kind" => "dict", "key_type" => key, "value_type" => value} ->
        key_spec = to_elixir_spec(key)
        value_spec = to_elixir_spec(value)
        quote do: %{optional(unquote(key_spec)) => unquote(value_spec)}

      %{"kind" => "tuple", "element_types" => types} ->
        type_specs = Enum.map(types, &to_elixir_spec/1)
        {:{}, [], type_specs}

      %{"kind" => "union", "union_types" => types} ->
        types
        |> Enum.map(&to_elixir_spec/1)
        |> Enum.reduce(fn spec, acc ->
          quote do: unquote(acc) | unquote(spec)
        end)

      %{"kind" => "literal", "values" => values, "base_type" => base} ->
        # Map literals to atoms if possible, otherwise string with comment
        if Enum.all?(values, &is_atom/1) do
          values
          |> Enum.map(&quote(do: unquote(&1)))
          |> Enum.reduce(fn spec, acc ->
            quote do: unquote(acc) | unquote(spec)
          end)
        else
          # Fallback to base type with comment
          map_primitive(base)
        end

      %{"kind" => "callable", "param_types" => params, "return_type" => ret} ->
        param_specs = Enum.map(params, &to_elixir_spec/1)
        return_spec = to_elixir_spec(ret)
        # Generate (param1, param2 -> return_type)
        quote do: (unquote_splicing(param_specs) -> unquote(return_spec))

      %{"kind" => "typevar", "name" => name, "constraints" => []} ->
        # Unconstrained TypeVar → use Elixir type variable
        var_name = String.to_atom(String.downcase(name))
        quote do: unquote(Macro.var(var_name, nil))

      %{"kind" => "typevar", "constraints" => constraints} when length(constraints) > 0 ->
        # Constrained TypeVar → generate union of constraints
        constraints
        |> Enum.map(&to_elixir_spec/1)
        |> Enum.reduce(fn spec, acc ->
          quote do: unquote(acc) | unquote(spec)
        end)

      %{"kind" => "class", "class_path" => path} ->
        # Map Python class to Elixir module
        module = python_class_to_elixir_module(path)
        quote do: unquote(module).t()

      _ ->
        quote do: term()
    end
  end

  defp map_primitive("int"), do: quote(do: integer())
  defp map_primitive("str"), do: quote(do: String.t())
  defp map_primitive("float"), do: quote(do: float())
  defp map_primitive("bool"), do: quote(do: boolean())
  defp map_primitive("bytes"), do: quote(do: binary())
  defp map_primitive("none"), do: quote(do: nil)
  defp map_primitive("any"), do: quote(do: term())
  defp map_primitive(_), do: quote(do: term())
end
```

### 4. Multi-Phase Introspection

**Goal**: Reduce latency and improve reliability with incremental introspection.

**Phases**:

1. **Fast Pass** (< 1s):
   - Extract module structure (functions, classes)
   - Extract names and signatures only
   - No type resolution, no docstring parsing

2. **Type Pass** (1-5s):
   - Resolve type hints
   - Parse docstrings
   - Extract detailed parameter information

3. **Deep Pass** (5-30s):
   - Introspect submodules
   - Analyze source code for purity hints
   - Extract examples and test cases

**Implementation**:
```python
def describe_library(self, module_path: str, discovery_depth: int = 2, phase: str = "full") -> dict:
    module = importlib.import_module(module_path)

    result = {
        "success": True,
        "library_version": getattr(module, "__version__", "unknown"),
        "phase": phase
    }

    if phase in ("fast", "full"):
        result["functions"] = self._introspect_functions_fast(module, module_path)
        result["classes"] = self._introspect_classes_fast(module, module_path)

    if phase in ("type", "full"):
        result["functions"] = self._enrich_with_types(result["functions"], module)
        result["classes"] = self._enrich_with_types(result["classes"], module)

    if phase == "full":
        result["submodules"] = self._introspect_submodules(module, module_path)
        result["constants"] = self._introspect_constants(module)
        result["enums"] = self._introspect_enums(module)

    return result
```

### 5. Type Stub Integration

**Goal**: Use `.pyi` stub files when available for better type information.

Many libraries (especially C extensions) ship with stub files that have richer type annotations than the runtime code.

**Implementation**:
```python
import importlib.util
import os

def find_stub_file(module):
    """Find .pyi stub file for module."""
    if hasattr(module, "__file__") and module.__file__:
        stub_path = module.__file__.replace(".py", ".pyi").replace(".so", ".pyi")
        if os.path.exists(stub_path):
            return stub_path

    # Check site-packages stubs
    module_name = module.__name__
    spec = importlib.util.find_spec(module_name)
    if spec and spec.origin:
        base = os.path.dirname(spec.origin)
        stub_path = os.path.join(base, module_name.split(".")[-1] + ".pyi")
        if os.path.exists(stub_path):
            return stub_path

    return None

def extract_types_from_stub(stub_path: str):
    """Parse .pyi file and extract type information."""
    import ast

    with open(stub_path) as f:
        tree = ast.parse(f.read())

    # Extract function signatures from AST
    # This gives us type information even when get_type_hints() fails
```

### 6. Validation and Testing

**Goal**: Ensure generated Elixir code is valid before committing to manifests.

**Validation Steps**:

1. **Syntax Validation**: Use `Code.string_to_quoted()` to validate Elixir code
2. **Typespec Validation**: Ensure generated specs are parseable
3. **Round-trip Testing**: Generate adapter → introspect → regenerate → diff

**Implementation**:
```elixir
defmodule SnakeBridge.Validator do
  def validate_generated_adapter(adapter_code) do
    # Parse Elixir code
    case Code.string_to_quoted(adapter_code) do
      {:ok, ast} ->
        # Extract and validate typespecs
        validate_typespecs(ast)
      {:error, _} = error ->
        error
    end
  end

  defp validate_typespecs(ast) do
    # Walk AST and find @spec attributes
    # Validate each spec is well-formed
  end
end
```

### 7. Caching and Incremental Updates

**Goal**: Avoid re-introspecting unchanged libraries.

**Strategy**:
- Hash module content (using `__file__` mtime or content hash)
- Cache introspection results in ETS or disk
- Invalidate cache when module changes

**Implementation**:
```python
import hashlib

def compute_module_hash(module):
    """Compute hash of module for cache validation."""
    if not hasattr(module, "__file__") or not module.__file__:
        return None

    try:
        with open(module.__file__, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except:
        return None

def describe_library_cached(self, module_path: str, **opts):
    module = importlib.import_module(module_path)
    module_hash = compute_module_hash(module)

    # Check cache
    cached = self.cache.get(module_path)
    if cached and cached["hash"] == module_hash:
        return cached["result"]

    # Introspect and cache
    result = self.describe_library(module_path, **opts)
    self.cache.set(module_path, {"hash": module_hash, "result": result})
    return result
```

---

## Summary and Roadmap

### Current State Assessment

| Component | Status | Quality |
|-----------|--------|---------|
| Function signature extraction | ✅ Working | Good |
| Parameter metadata (kinds, defaults) | ✅ Working | Good |
| Basic type extraction | ⚠️ Partial | Poor (falls back to `any` often) |
| Complex type handling | ❌ Missing | N/A |
| Docstring extraction | ✅ Working | Fair (raw strings only) |
| Docstring parsing | ❌ Missing | N/A |
| Class introspection | ✅ Working | Good |
| Property introspection | ⚠️ Partial | Fair |
| Submodule enumeration | ✅ Working | Good |
| Elixir type mapping | ⚠️ Partial | Fair |

### Recommended v2 Implementation Priority

**P0 (Must Have)**:
1. Enhanced type descriptor extraction with proper Union, Literal, Callable support
2. Improved `_type_to_string()` replacement with structured descriptors
3. Updated `TypeSystem.Mapper` to handle new descriptors
4. Validation framework for generated code

**P1 (Should Have)**:
5. Docstring parsing with `docstring_parser`
6. TypeVar handling (at minimum, erase to `term()` with typespec variables)
7. Stub file integration for C extensions
8. Deprecation detection and documentation

**P2 (Nice to Have)**:
9. Multi-phase introspection for performance
10. Caching and incremental updates
11. Constant and enum extraction
12. AST-based purity analysis

### Metrics for Success

1. **Type Coverage**: % of parameters with non-`any` types → Target: >60% (up from ~20% current)
2. **Docstring Coverage**: % of functions with parsed docstrings → Target: >80%
3. **Type Mapping Accuracy**: Manual review of top 20 libraries → Target: 90% correct mappings
4. **Generation Time**: P99 latency for introspection → Target: <10s for large libraries
5. **Dialyzer Pass Rate**: % of generated adapters that pass Dialyzer → Target: 100%

---

**End of Document**
