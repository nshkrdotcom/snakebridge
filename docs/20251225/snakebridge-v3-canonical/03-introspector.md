# Python Introspector

## Purpose

The introspector queries Python to extract function signatures, docstrings, and type hints. This data drives code generation.

## How It Works

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ Symbols to      │     │ Introspection   │     │ Structured      │
│ Generate        │────►│ Script          │────►│ Metadata        │
│                 │     │ (via uv/python) │     │                 │
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

## Implementation

### Python Script

```python
# Introspection script (embedded in Elixir, executed via UV)
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
  Introspects Python functions using UV/Python.
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
      max_concurrency: 4,
      timeout: 30_000
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  defp run_python(library, script, args) do
    {cmd, cmd_args} = build_command(library, script, args)
    
    case System.cmd(cmd, cmd_args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {error, code} -> {:error, {code, error}}
    end
  end

  defp build_command(library, script, args) do
    if library.version == :stdlib do
      # Stdlib: use system Python
      {"python3", ["-c", script | args]}
    else
      # Third-party: use UV with the specific version
      version_spec = "#{library.python_name}#{library.version}"
      {"uv", ["run", "--with", version_spec, "python", "-c", script | args]}
    end
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

## Type Mapping

The introspector extracts Python type annotations, which are later mapped to Elixir typespecs.

| Python Annotation | Elixir Typespec |
|-------------------|-----------------|
| `int` | `integer()` |
| `float` | `float()` |
| `str` | `String.t()` |
| `bool` | `boolean()` |
| `None` | `nil` |
| `list` | `list()` |
| `dict` | `map()` |
| `Any` | `term()` |
| `Optional[T]` | `T \| nil` |
| `ndarray` | `reference()` |
| Unknown | `term()` |

Complex annotations (generics, unions) are simplified to `term()` for safety.

## Submodule Handling

For submodules like `numpy.linalg`:

```elixir
# Detected: Numpy.Linalg.solve/2
# Introspect from: numpy.linalg.solve

introspect(%{python_name: "numpy.linalg"}, [:solve])
```

The introspector handles dotted module names:

```python
# For "numpy.linalg"
import numpy.linalg as module
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
      "generated_at": "2025-12-25T10:00:00Z",
      "introspection": {
        "parameters": [...],
        "docstring": "..."
      }
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
