# SnakeBridge v2 Architecture Synthesis

**Date**: 2025-12-24
**Status**: Final Architecture Recommendation
**Based on**: Research documents 01-08 from this directory

---

## Executive Summary

SnakeBridge v2 should be a **compile-time code generator** that produces fully-documented, fully-typed Elixir modules from Python library introspection. The key insight is that the current runtime generation approach sacrifices too much tooling benefit for flexibility that isn't needed.

**Core Design Principles**:
1. **Offline Generation**: `mix snakebridge.gen numpy` → `lib/snakebridge/adapters/numpy.ex`
2. **Source Files Over AST**: Generated `.ex` files, not runtime `Code.compile_quoted/1`
3. **Documentation First**: Parse Python docstrings → Elixir `@doc` with full HexDocs rendering
4. **Type-Tagged Serialization**: Lossless Python ↔ Elixir type conversion via JSON + metadata
5. **Minimal Runtime**: Thin wrapper over Snakepit, no registries or allowlists

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     GENERATION TIME (Offline)                    │
│                                                                  │
│  mix snakebridge.gen numpy                                       │
│         │                                                        │
│         ▼                                                        │
│  ┌─────────────────────────────────────────────────────┐        │
│  │  Python Introspection Script                         │        │
│  │  - inspect.signature() for all functions             │        │
│  │  - typing.get_type_hints() for types                 │        │
│  │  - docstring_parser for structured docs              │        │
│  │  - Output: introspection.json                        │        │
│  └─────────────────────────────────────────────────────┘        │
│         │                                                        │
│         ▼                                                        │
│  ┌─────────────────────────────────────────────────────┐        │
│  │  Elixir Generator                                    │        │
│  │  - TypeMapper: Python types → @spec                  │        │
│  │  - DocFormatter: Python docstrings → @doc            │        │
│  │  - SourceWriter: AST → formatted .ex file            │        │
│  │  - Output: lib/snakebridge/adapters/numpy.ex         │        │
│  └─────────────────────────────────────────────────────┘        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      COMPILE TIME (Mix)                          │
│                                                                  │
│  lib/snakebridge/adapters/numpy.ex                               │
│         │                                                        │
│         ▼                                                        │
│  Standard Mix Compilation                                        │
│  - Dialyzer analysis ✓                                           │
│  - ExDoc generation ✓                                            │
│  - IDE autocomplete ✓                                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      RUNTIME (Production)                        │
│                                                                  │
│  User Code                                                       │
│         │                                                        │
│         ▼                                                        │
│  SnakeBridge.NumPy.array([1, 2, 3])                             │
│         │                                                        │
│         ▼                                                        │
│  ┌─────────────────────────────────────────────────────┐        │
│  │  Generated Module (thin wrapper)                     │        │
│  │  - Serialize args via SnakeBridge.Types.encode/1     │        │
│  │  - Call Snakepit.execute/3                           │        │
│  │  - Deserialize result via SnakeBridge.Types.decode/1 │        │
│  └─────────────────────────────────────────────────────┘        │
│         │                                                        │
│         ▼                                                        │
│  Snakepit (gRPC) → Python Worker → Result                       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Module Structure

```
lib/
├── snakebridge.ex                    # Main API entry point
├── snakebridge/
│   ├── runtime.ex                    # Snakepit integration (thin)
│   │
│   ├── types/
│   │   ├── encoder.ex                # Elixir → tagged JSON
│   │   ├── decoder.ex                # Tagged JSON → Elixir
│   │   └── protocols.ex              # SnakeBridge.Encode/Decode protocols
│   │
│   ├── generator/
│   │   ├── introspector.ex           # Run Python introspection
│   │   ├── type_mapper.ex            # Python types → Elixir @spec
│   │   ├── doc_parser.ex             # Docstring → @doc formatting
│   │   └── source_writer.ex          # AST → formatted .ex source
│   │
│   └── adapters/                     # GENERATED (committed to git)
│       ├── numpy.ex
│       ├── requests.ex
│       ├── pandas.ex
│       └── ...
│
├── mix/
│   └── tasks/
│       └── snakebridge/
│           └── gen.ex                # mix snakebridge.gen <library>
│
priv/
└── python/
    └── introspect.py                 # Python introspection script
```

**Total: ~15-20 modules** (vs current ~40+)

---

## Type System Design

### Problem Statement

Python and Elixir have fundamentally different type systems:
- **Python**: Dynamic, gradually typed, mutable, class-based
- **Elixir**: Dynamic, pattern-matched, immutable, protocol-based
- **JSON**: No tuples, no sets, string-only keys, no binary, no infinity/NaN

### Solution: Tagged Type Serialization

**Principle**: Every non-trivial type gets a `__type__` tag for lossless round-tripping.

```python
# Python encoder (priv/python/snakebridge_types.py)
def encode(value):
    if isinstance(value, tuple):
        return {"__type__": "tuple", "elements": [encode(v) for v in value]}
    if isinstance(value, set):
        return {"__type__": "set", "elements": [encode(v) for v in value]}
    if isinstance(value, bytes):
        return {"__type__": "bytes", "encoding": "base64", "data": base64.b64encode(value).decode()}
    if isinstance(value, complex):
        return {"__type__": "complex", "real": value.real, "imag": value.imag}
    if isinstance(value, float):
        if math.isinf(value):
            return {"__type__": "float", "value": "Infinity" if value > 0 else "-Infinity"}
        if math.isnan(value):
            return {"__type__": "float", "value": "NaN"}
        return value
    if isinstance(value, datetime):
        return {"__type__": "datetime", "iso": value.isoformat()}
    # ... etc
    return value  # primitives pass through
```

```elixir
# Elixir decoder (lib/snakebridge/types/decoder.ex)
defmodule SnakeBridge.Types.Decoder do
  def decode(%{"__type__" => "tuple", "elements" => elements}) do
    List.to_tuple(Enum.map(elements, &decode/1))
  end

  def decode(%{"__type__" => "set", "elements" => elements}) do
    MapSet.new(Enum.map(elements, &decode/1))
  end

  def decode(%{"__type__" => "bytes", "encoding" => "base64", "data" => data}) do
    Base.decode64!(data)
  end

  def decode(%{"__type__" => "complex", "real" => r, "imag" => i}) do
    %Complex{real: r, imaginary: i}  # or use a tuple {:complex, r, i}
  end

  def decode(%{"__type__" => "float", "value" => "Infinity"}), do: :infinity
  def decode(%{"__type__" => "float", "value" => "-Infinity"}), do: :neg_infinity
  def decode(%{"__type__" => "float", "value" => "NaN"}), do: :nan

  def decode(%{"__type__" => "datetime", "iso" => iso}) do
    DateTime.from_iso8601!(iso)
  end

  def decode(list) when is_list(list), do: Enum.map(list, &decode/1)
  def decode(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, decode(v)} end)
  def decode(value), do: value  # primitives
end
```

### Type Spec Generation

Map Python type annotations to Elixir `@spec`:

| Python Type | Elixir Spec |
|-------------|-------------|
| `int` | `integer()` |
| `float` | `float()` |
| `str` | `String.t()` |
| `bool` | `boolean()` |
| `None` | `nil` |
| `bytes` | `binary()` |
| `list[T]` | `[T_spec]` |
| `tuple[A, B, C]` | `{A_spec, B_spec, C_spec}` |
| `dict[K, V]` | `%{K_spec => V_spec}` |
| `set[T]` | `MapSet.t(T_spec)` |
| `Optional[T]` | `T_spec \| nil` |
| `Union[A, B]` | `A_spec \| B_spec` |
| `Any` | `any()` |
| `Callable[[A], R]` | `(A_spec -> R_spec)` |
| Untyped | `any()` |

---

## Documentation Generation

### Python Docstring Parsing

Use `docstring_parser` library (pip install docstring_parser) to parse Google, NumPy, and Sphinx docstring formats:

```python
import docstring_parser

doc = docstring_parser.parse(func.__doc__)

result = {
    "short_description": doc.short_description,
    "long_description": doc.long_description,
    "params": [
        {"name": p.arg_name, "description": p.description, "type": p.type_name}
        for p in doc.params
    ],
    "returns": {
        "description": doc.returns.description if doc.returns else None,
        "type": doc.returns.type_name if doc.returns else None
    },
    "raises": [
        {"type": e.type_name, "description": e.description}
        for e in doc.raises
    ],
    "examples": [e.snippet for e in doc.examples]
}
```

### Elixir @doc Formatting

Transform parsed docstrings into rich Elixir documentation:

```elixir
@doc """
Create an array from the given data.

## Parameters

- `data` (`list`) - Array data. Can be nested lists for multi-dimensional arrays.
- `dtype` (`String.t()`, optional) - Desired data type. Defaults to inferred type.

## Returns

`{:ok, ndarray}` - A NumPy array object.

## Examples

    iex> {:ok, arr} = SnakeBridge.NumPy.array([1, 2, 3])
    {:ok, %{"shape" => [3], "dtype" => "int64", ...}}

## Raises

- `ValueError` - If data cannot be converted to array.

---

*Ported from Python's `numpy.array`*
"""
@spec array(data :: list(), opts :: keyword()) :: {:ok, map()} | {:error, term()}
def array(data, opts \\ []) do
  # ...
end
```

---

## Generator Implementation

### Mix Task: `mix snakebridge.gen`

```elixir
defmodule Mix.Tasks.Snakebridge.Gen do
  use Mix.Task

  @shortdoc "Generate Elixir adapter for a Python library"

  @moduledoc """
  Generates a fully-typed, fully-documented Elixir module from Python introspection.

  ## Usage

      mix snakebridge.gen numpy
      mix snakebridge.gen requests --functions get,post,put,delete
      mix snakebridge.gen pandas --output lib/my_app/python/pandas.ex

  ## Options

    * `--output` - Output path (default: lib/snakebridge/adapters/<library>.ex)
    * `--functions` - Comma-separated list of functions to include
    * `--exclude` - Comma-separated list of functions to exclude
    * `--module` - Custom Elixir module name
    * `--force` - Overwrite existing file
  """

  def run(args) do
    {opts, [library], _} = OptionParser.parse(args,
      strict: [output: :string, functions: :string, exclude: :string,
               module: :string, force: :boolean])

    # 1. Ensure Python dependencies
    ensure_introspection_deps!()

    # 2. Run Python introspection
    introspection = SnakeBridge.Generator.Introspector.introspect(library)

    # 3. Generate Elixir source
    source = SnakeBridge.Generator.SourceWriter.generate(introspection, opts)

    # 4. Write file
    output_path = opts[:output] || "lib/snakebridge/adapters/#{library}.ex"
    File.write!(output_path, source)

    Mix.shell().info("Generated #{output_path}")
  end
end
```

### Python Introspection Script

```python
#!/usr/bin/env python3
"""
priv/python/introspect.py

Comprehensive Python library introspector for SnakeBridge code generation.
"""

import sys
import json
import inspect
import importlib
from typing import get_type_hints, Any, get_origin, get_args

try:
    import docstring_parser
except ImportError:
    docstring_parser = None


def introspect_module(module_name: str) -> dict:
    """
    Introspect a Python module and return structured metadata.
    """
    module = importlib.import_module(module_name)

    return {
        "name": module_name,
        "doc": inspect.getdoc(module),
        "functions": [
            introspect_function(name, func)
            for name, func in inspect.getmembers(module, inspect.isfunction)
            if not name.startswith('_') and func.__module__ == module_name
        ],
        "classes": [
            introspect_class(name, cls)
            for name, cls in inspect.getmembers(module, inspect.isclass)
            if not name.startswith('_') and cls.__module__ == module_name
        ]
    }


def introspect_function(name: str, func) -> dict:
    """Extract function metadata."""
    sig = inspect.signature(func)

    # Get type hints safely
    try:
        hints = get_type_hints(func)
    except Exception:
        hints = {}

    # Parse docstring
    doc_parsed = None
    if docstring_parser and func.__doc__:
        try:
            doc_parsed = parse_docstring(func.__doc__)
        except Exception:
            pass

    return {
        "name": name,
        "doc": inspect.getdoc(func),
        "doc_parsed": doc_parsed,
        "parameters": [
            introspect_parameter(p, hints.get(p.name))
            for p in sig.parameters.values()
        ],
        "return_type": type_to_dict(hints.get('return', Any)),
        "is_generator": inspect.isgeneratorfunction(func),
        "is_async": inspect.iscoroutinefunction(func),
    }


def introspect_parameter(param: inspect.Parameter, type_hint) -> dict:
    """Extract parameter metadata."""
    result = {
        "name": param.name,
        "kind": param.kind.name.lower(),
        "required": param.default is inspect.Parameter.empty,
    }

    if param.default is not inspect.Parameter.empty:
        try:
            result["default"] = repr(param.default)
            result["default_value"] = serialize_default(param.default)
        except Exception:
            result["default"] = "..."

    if type_hint is not None:
        result["type"] = type_to_dict(type_hint)
    elif param.annotation is not inspect.Parameter.empty:
        result["type"] = type_to_dict(param.annotation)

    return result


def type_to_dict(t) -> dict:
    """Convert a type annotation to a serializable dict."""
    if t is None or t is type(None):
        return {"kind": "none"}

    origin = get_origin(t)
    args = get_args(t)

    if origin is None:
        # Simple type
        if t is Any:
            return {"kind": "any"}
        if t is int:
            return {"kind": "primitive", "name": "int"}
        if t is float:
            return {"kind": "primitive", "name": "float"}
        if t is str:
            return {"kind": "primitive", "name": "str"}
        if t is bool:
            return {"kind": "primitive", "name": "bool"}
        if t is bytes:
            return {"kind": "primitive", "name": "bytes"}
        # Class reference
        return {"kind": "class", "name": getattr(t, '__name__', str(t))}

    # Generic types
    if origin is list:
        return {"kind": "list", "element": type_to_dict(args[0]) if args else {"kind": "any"}}
    if origin is dict:
        return {
            "kind": "dict",
            "key": type_to_dict(args[0]) if args else {"kind": "any"},
            "value": type_to_dict(args[1]) if len(args) > 1 else {"kind": "any"}
        }
    if origin is tuple:
        return {"kind": "tuple", "elements": [type_to_dict(a) for a in args]}
    if origin is set:
        return {"kind": "set", "element": type_to_dict(args[0]) if args else {"kind": "any"}}
    if origin is type(None):
        return {"kind": "none"}

    # Union (including Optional)
    import typing
    if origin is typing.Union:
        return {"kind": "union", "types": [type_to_dict(a) for a in args]}

    # Fallback
    return {"kind": "any", "raw": str(t)}


def parse_docstring(docstring: str) -> dict:
    """Parse docstring using docstring_parser."""
    doc = docstring_parser.parse(docstring)
    return {
        "short": doc.short_description,
        "long": doc.long_description,
        "params": [
            {"name": p.arg_name, "description": p.description, "type": p.type_name}
            for p in doc.params
        ],
        "returns": {
            "description": doc.returns.description,
            "type": doc.returns.type_name
        } if doc.returns else None,
        "raises": [
            {"type": e.type_name, "description": e.description}
            for e in doc.raises
        ],
        "examples": [
            {"description": e.description, "snippet": e.snippet}
            for e in getattr(doc, 'examples', [])
        ]
    }


def serialize_default(value):
    """Serialize a default value for JSON."""
    if value is None:
        return None
    if isinstance(value, (bool, int, float, str)):
        return value
    if isinstance(value, (list, tuple)):
        return [serialize_default(v) for v in value]
    if isinstance(value, dict):
        return {str(k): serialize_default(v) for k, v in value.items()}
    return repr(value)


if __name__ == "__main__":
    module_name = sys.argv[1]
    result = introspect_module(module_name)
    print(json.dumps(result, indent=2))
```

---

## Generated Module Example

```elixir
# lib/snakebridge/adapters/json.ex
# Generated by mix snakebridge.gen json

defmodule SnakeBridge.Json do
  @moduledoc """
  Elixir wrapper for Python's `json` module.

  Provides JSON encoding and decoding functionality using Python's standard library.

  ## Usage

      {:ok, json_string} = SnakeBridge.Json.dumps(%{name: "Alice", age: 30})
      # => {:ok, "{\"name\": \"Alice\", \"age\": 30}"}

      {:ok, data} = SnakeBridge.Json.loads(json_string)
      # => {:ok, %{"name" => "Alice", "age" => 30}}

  ---

  *Generated by SnakeBridge from Python `json` module introspection*
  """

  alias SnakeBridge.{Runtime, Types}

  @doc """
  Serialize `obj` to a JSON formatted string.

  ## Parameters

  - `obj` (`any()`) - The object to serialize. Must be JSON-serializable.
  - `opts` - Optional keyword list:
    - `:indent` (`integer() | nil`) - Indentation level for pretty-printing.
    - `:sort_keys` (`boolean()`) - Sort dictionary keys. Default: `false`.
    - `:ensure_ascii` (`boolean()`) - Escape non-ASCII. Default: `true`.

  ## Returns

  `{:ok, String.t()}` on success, `{:error, term()}` on failure.

  ## Examples

      iex> SnakeBridge.Json.dumps(%{a: 1, b: 2})
      {:ok, "{\"a\": 1, \"b\": 2}"}

      iex> SnakeBridge.Json.dumps(%{a: 1}, indent: 2)
      {:ok, "{\\n  \"a\": 1\\n}"}
  """
  @spec dumps(obj :: any(), opts :: keyword()) :: {:ok, String.t()} | {:error, term()}
  def dumps(obj, opts \\ []) do
    args = %{obj: Types.encode(obj)}

    args =
      opts
      |> Enum.reduce(args, fn
        {:indent, v}, acc -> Map.put(acc, :indent, v)
        {:sort_keys, v}, acc -> Map.put(acc, :sort_keys, v)
        {:ensure_ascii, v}, acc -> Map.put(acc, :ensure_ascii, v)
        _, acc -> acc
      end)

    case Runtime.call("json", "dumps", args) do
      {:ok, result} -> {:ok, Types.decode(result)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Deserialize `s` (a JSON string) to a Python object.

  ## Parameters

  - `s` (`String.t()`) - The JSON string to parse.

  ## Returns

  `{:ok, any()}` - The parsed data structure.

  ## Examples

      iex> SnakeBridge.Json.loads("{\"name\": \"Bob\"}")
      {:ok, %{"name" => "Bob"}}
  """
  @spec loads(s :: String.t()) :: {:ok, any()} | {:error, term()}
  def loads(s) when is_binary(s) do
    case Runtime.call("json", "loads", %{s: s}) do
      {:ok, result} -> {:ok, Types.decode(result)}
      {:error, _} = error -> error
    end
  end
end
```

---

## What Gets Removed

The following current v1/v2 components are **eliminated**:

| Component | Reason |
|-----------|--------|
| `Manifest.Registry` | Security theater; manifest IS the allowlist |
| `Manifest.Loader` (runtime) | Replaced by compile-time generation |
| `Manifest.Agent` | No runtime manifest management |
| `Generator.Hooks` | Compilation mode irrelevant |
| `Adapter.Creator` | Replaced by simpler mix task |
| `Adapter.AgentOrchestrator` | No AI needed for deterministic introspection |
| `Adapter.Agents.*` | See above |
| `Adapter.CodingAgent` | See above |
| `Discovery.*` | Introspection moved to generation time |
| `Schema.*` | Not needed |
| `Config` struct | Manifest dict is sufficient |
| `Cache` (GenServer) | Let Snakepit handle caching |

**Estimated reduction**: ~40 modules → ~15 modules

---

## Implementation Phases

### Phase 1: Core Type System (Week 1)
- `SnakeBridge.Types.Encoder` - Elixir → tagged JSON
- `SnakeBridge.Types.Decoder` - Tagged JSON → Elixir
- Test with all edge cases: tuples, sets, bytes, datetime, inf/nan

### Phase 2: Python Introspection (Week 1-2)
- `priv/python/introspect.py` - Full introspection with docstring parsing
- Handle complex types (generics, unions, callables)
- Test against numpy, requests, pandas

### Phase 3: Elixir Generator (Week 2)
- `SnakeBridge.Generator.TypeMapper` - Python types → @spec
- `SnakeBridge.Generator.DocParser` - Docstring → @doc
- `SnakeBridge.Generator.SourceWriter` - AST → .ex file

### Phase 4: Mix Task & Polish (Week 2-3)
- `mix snakebridge.gen` task
- Generate adapters for 10+ libraries
- ExDoc integration and HexDocs quality

### Phase 5: Migration & Release (Week 3)
- Deprecate v1 API (if needed)
- Migration guide
- Release v2.0.0

---

## Success Criteria

1. **`mix snakebridge.gen numpy`** produces a ~2000 line `.ex` file with full @doc and @spec
2. **HexDocs** renders beautifully with parameter descriptions, examples, types
3. **Dialyzer** passes with no warnings on generated code
4. **IDE autocomplete** works perfectly
5. **Round-trip types** work: Elixir tuple → Python → Elixir tuple (not list)
6. **Line count** reduced from ~8000 to ~2000

---

## Appendix: Key Research Insights

### From Snakepit Core Architecture (01)
- gRPC/HTTP2 is the right choice for transport
- Stateless workers, stateful BEAM is the right pattern
- Don't reinvent pool management; use Snakepit's

### From Type Mapping Impedance (05)
- ~70% of types work through JSON unchanged
- 30% need tagged encoding (tuples, sets, bytes, datetime, complex, inf/nan)
- Must be bidirectional (Elixir ↔ Python)

### From Current SnakeBridge Critique (06)
- Too many abstraction layers (7-8 hops)
- Config vs Manifest duality is confusing
- Runtime allowlist is security theater
- Over-engineering for simple introspection task

### From Elixir Metaprogramming (04)
- Source file generation > runtime AST compilation
- Mix compiler integration is standard (Phoenix, Ecto do this)
- Required for ExDoc, Dialyzer, IDE support

### From Prior Art (08)
- PyO3's trait-based type conversion is the gold standard
- Always generate stub files (`.pyi` for Python, `.ex` for Elixir)
- Runtime introspection for generation, compile-time for production
