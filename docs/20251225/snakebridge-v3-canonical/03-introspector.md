# Python Introspector

## Purpose

The introspector queries Python to extract function signatures, docstrings, and type hints. This data drives code generation.

## How It Works

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ Symbols to      │     │ Introspection   │     │ Structured      │
│ Generate        │────►│ Script          │────►│ Metadata        │
│                 │     │ (via Snakepit)  │     │                 │
│ [array, mean]   │     │                 │     │ [{name, params, │
│                 │     │                 │     │   doc, ...}]    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

## Introspection Data

For each function, we extract:

```json
{
  "name": "array",
  "parameters": [
    {
      "name": "object",
      "kind": "POSITIONAL_OR_KEYWORD",
      "annotation": "ArrayLike"
    },
    {
      "name": "dtype",
      "kind": "KEYWORD_ONLY",
      "default": "None",
      "annotation": "DTypeLike | None"
    },
    {
      "name": "copy",
      "kind": "KEYWORD_ONLY", 
      "default": "True",
      "annotation": "bool"
    }
  ],
  "return_annotation": "ndarray",
  "docstring": "Create an array.\n\nParameters\n----------\nobject : array_like\n    ...",
  "callable": true,
  "module": "numpy"
}
```

## Class Introspection

When a symbol is a class, the introspector emits structured metadata:

```json
{
  "name": "Symbol",
  "type": "class",
  "docstring": "Symbol class...",
  "methods": [
    {"name": "__init__", "parameters": [...], "docstring": "..."},
    {"name": "simplify", "parameters": [...], "docstring": "..."}
  ],
  "attributes": ["name", "is_commutative"]
}
```

Class metadata is used by the generator to create nested modules and method wrappers.

## Implementation

### Python Script

```python
# Introspection script (embedded in Elixir, executed via Snakepit runtime)
import inspect
import json
import sys

def introspect_functions(module_name, functions):
    """Introspect a list of functions from a module."""
    try:
        module = __import__(module_name)
    except ImportError as e:
        return {"error": f"Cannot import {module_name}: {e}"}
    
    results = []
    for func_name in functions:
        obj = getattr(module, func_name, None)
        if obj is None:
            results.append({"name": func_name, "error": "not_found"})
            continue
        
        info = {
            "name": func_name,
            "callable": callable(obj),
            "module": module_name
        }
        
        # Signature
        try:
            sig = inspect.signature(obj)
            params = []
            for p in sig.parameters.values():
                param = {
                    "name": p.name,
                    "kind": p.kind.name
                }
                if p.default != inspect.Parameter.empty:
                    param["default"] = repr(p.default)
                if p.annotation != inspect.Parameter.empty:
                    param["annotation"] = _format_annotation(p.annotation)
                params.append(param)
            info["parameters"] = params
            
            if sig.return_annotation != inspect.Signature.empty:
                info["return_annotation"] = _format_annotation(sig.return_annotation)
        except (ValueError, TypeError):
            info["parameters"] = []
        
        # Docstring
        doc = inspect.getdoc(obj)
        if doc:
            info["docstring"] = doc[:8000]  # Limit size
        
        results.append(info)
    
    return results

def _format_annotation(annotation):
    """Format a type annotation to string."""
    if hasattr(annotation, '__name__'):
        return annotation.__name__
    return str(annotation)

if __name__ == "__main__":
    module_name = sys.argv[1]
    functions = json.loads(sys.argv[2])
    result = introspect_functions(module_name, functions)
    print(json.dumps(result))
```

### Elixir Module

```elixir
defmodule SnakeBridge.Introspector do
  @moduledoc """
  Introspects Python functions using the Snakepit Python runtime.
  """

  @doc """
  Introspect a list of functions from a library.
  Returns {:ok, [info]} or {:error, reason}.
  """
  def introspect(library, functions) when is_list(functions) do
    script = introspection_script()
    functions_json = Jason.encode!(Enum.map(functions, &to_string/1))
    
    case run_python(library, script, [library.python_name, functions_json]) do
      {:ok, output} -> parse_output(output)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Batch introspect multiple libraries efficiently.
  """
  def introspect_batch(libs_and_functions) do
    libs_and_functions
    |> Task.async_stream(
      fn {library, functions} ->
        {library, introspect(library, functions)}
      end,
      max_concurrency: config().introspector.max_concurrency || System.schedulers_online(),
      timeout: config().introspector.timeout || 30_000
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  defp run_python(library, script, args) do
    # Delegate runtime selection (uv/system/managed) to Snakepit.
    Snakepit.Python.run(library, script, args)
  end

  defp parse_output(output) do
    case Jason.decode(output) do
      {:ok, results} when is_list(results) -> {:ok, results}
      {:ok, %{"error" => error}} -> {:error, error}
      {:error, _} -> {:error, {:json_parse, output}}
    end
  end

  defp introspection_script do
    # Embedded Python script (see above)
    ~S"""
    import inspect
    import json
    import sys
    ...
    """
  end
end
```

Note: `Snakepit.Python.run/3` is illustrative. SnakeBridge delegates runtime
selection to Snakepit Prime; the actual entrypoint lives in Snakepit.

## Python Runtime Integration (Snakepit)

SnakeBridge does not manage Python directly. Introspection runs inside the
Python runtime configured in Snakepit (uv-managed or system). Missing Python
or uv errors surface from Snakepit and are forwarded by SnakeBridge.

## Batching Strategy

Introspection is I/O-bound (starting Python, loading libraries). We optimize by:

1. **Batch per library**: One Python invocation per library, not per function
2. **Parallel across libraries**: Multiple libraries introspected concurrently
3. **Caching**: Results cached in manifest; re-introspect only new symbols

```elixir
# Efficient: one call for all numpy functions
{:ok, results} = Introspector.introspect(numpy_lib, [:array, :zeros, :mean, :std])

# Parallel: all libraries at once
results = Introspector.introspect_batch([
  {numpy_lib, [:array, :zeros]},
  {pandas_lib, [:DataFrame, :read_csv]},
  {sympy_lib, [:Symbol, :solve]}
])
```

### Concurrency Controls

```elixir
config :snakebridge,
  introspector: [
    max_concurrency: 4,
    timeout: 30_000
  ]
```

`max_concurrency` caps parallel library introspections to avoid CPU and I/O saturation.

## Error Handling

### Function Not Found

```elixir
introspect(numpy, [:nonexistent])
# → {:ok, [%{"name" => "nonexistent", "error" => "not_found"}]}
```

Non-existent functions are skipped with a warning, not a failure.

### Import Error

```elixir
introspect(uninstalled_lib, [:func])
# → {:error, "Cannot import somelib: No module named 'somelib'"}
```

### Timeout

```elixir
# Default timeout: 30 seconds
# Configurable for large libraries

introspect(huge_lib, many_functions, timeout: 60_000)
```

### Python Runtime Missing

If Snakepit cannot locate Python or uv, introspection fails:

- `:stdlib` libraries fail with `{:error, :python_not_found}`
- Third-party libraries fail with `{:error, :uv_not_found}` (from Snakepit)

`mix snakebridge.doctor` should surface install guidance (delegated to Snakepit).

## Type Mapping

The introspector extracts Python type annotations, which are later mapped to Elixir typespecs. See [13-typespecs.md](13-typespecs.md) for the full mapping and edge cases.

Quick examples:

| Python Annotation | Elixir Typespec |
|-------------------|-----------------|
| `int` | `integer()` |
| `float` | `float()` |
| `str` | `String.t()` |
| `Optional[T]` | `T \| nil` |
| `Any` | `term()` |

## Submodule Handling

For submodules like `numpy.linalg`:

```elixir
# Detected: Numpy.Linalg.solve/2
# Introspect from: numpy.linalg.solve

introspect(%{python_name: "numpy.linalg"}, [:solve])
```

The introspector handles dotted module names via importlib:

```python
import importlib
module = importlib.import_module("numpy.linalg")
getattr(module, "solve")
```

## Caching

Introspection results are cached in the manifest. Re-introspection happens when:

1. New symbol detected (not in manifest)
2. Library version changed (lock file mismatch)
3. Force regeneration (`mix snakebridge.generate --force`)

```json
// .snakebridge/manifest.json
{
  "symbols": {
    "Numpy.array/1": {
      "python_name": "array",
      "signature": "(object, dtype=None, ...)",
      "doc_hash": "sha256:..."
    }
  }
}
```

## Performance

| Operation | Typical Time |
|-----------|--------------|
| Single function introspection | 50-100ms |
| 10 functions (batched) | 100-200ms |
| 100 functions (batched) | 500-1000ms |
| Full numpy (800+ functions) | 3-5s |

Cold start (first run) is slower due to Python/library loading. Subsequent runs benefit from OS-level caching.
