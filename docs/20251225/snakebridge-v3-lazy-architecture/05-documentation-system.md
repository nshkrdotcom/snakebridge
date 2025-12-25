# Documentation System

## The Documentation Problem

In v2, we generated complete ExDoc documentation for every function in every library. For sympy alone, this meant:
- 481 functions with full docstrings
- 392 classes with method documentation
- Minutes of generation time
- Megabytes of HTML/markdown

Most of this documentation is never read.

## The v3 Solution: Docs as Query

Instead of building static documentation artifacts, v3 treats documentation as a **queryable data source** that returns results on demand.

```
Traditional:  Build all docs → Search locally → Find answer
v3 Approach:  Query on demand → Return answer → Cache for speed
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Developer Request                               │
│                                                                         │
│   iex> Numpy.doc(:array)                                               │
│   iex> h Numpy.array                                                    │
│   iex> Numpy.search("matrix multiply")                                  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      SnakeBridge.Docs                                   │
│                                                                         │
│   1. Check doc cache                                                    │
│   2. If cached: return immediately                                      │
│   3. If not: query Python for docstring                                 │
│   4. Parse and format                                                   │
│   5. Cache result                                                       │
│   6. Return to developer                                                │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                        ┌───────────┴───────────┐
                        ▼                       ▼
               ┌──────────────┐        ┌──────────────┐
               │  Cache Hit   │        │ Cache Miss   │
               │    <1ms      │        │   ~50ms      │
               └──────────────┘        └──────────────┘
```

## API

### Function Documentation

```elixir
# Get documentation for a specific function
iex> Numpy.doc(:array)
"""
numpy.array(object, dtype=None, *, copy=True, order='K', subok=False, ndmin=0, like=None)

Create an array.

Parameters
----------
object : array_like
    An array, any object exposing the array interface, an object whose
    __array__ method returns an array, or any (nested) sequence.
dtype : data-type, optional
    The desired data-type for the array. If not given, then the type
    will be determined as the minimum type required to hold the objects
    in the sequence.
...
"""

# Also works with IEx helper
iex> h Numpy.array
# (same output, formatted for terminal)
```

### Search

```elixir
# Search by keyword
iex> Numpy.search("matrix multiply")
[
  %{
    name: :matmul,
    signature: "matmul(x1, x2, /)",
    summary: "Matrix product of two arrays.",
    relevance: 0.95
  },
  %{
    name: :dot,
    signature: "dot(a, b, out=None)",
    summary: "Dot product of two arrays.",
    relevance: 0.87
  },
  %{
    name: :multiply,
    signature: "multiply(x1, x2, /)",
    summary: "Multiply arguments element-wise.",
    relevance: 0.72
  }
]

# Search with filters
iex> Numpy.search("array", type: :class)
iex> Numpy.search("solve", module: "linalg")
```

### Browse

```elixir
# List available functions (from cache + quick introspection)
iex> Numpy.functions()
[:abs, :add, :all, :allclose, :amax, :amin, :any, :append, :arange, :arccos, ...]

# List with brief descriptions
iex> Numpy.functions(brief: true)
[
  {:abs, "Calculate the absolute value element-wise."},
  {:add, "Add arguments element-wise."},
  {:all, "Test whether all array elements..."},
  ...
]

# List submodules
iex> Numpy.submodules()
[:linalg, :fft, :random, :polynomial, ...]

# List classes
iex> Numpy.classes()
[:ndarray, :dtype, :matrix, ...]
```

### Examples

```elixir
# Get usage examples for a function
iex> Numpy.examples(:array)
[
  %{
    code: """
    >>> np.array([1, 2, 3])
    array([1, 2, 3])
    """,
    description: "Create a 1D array"
  },
  %{
    code: """
    >>> np.array([[1, 2], [3, 4]])
    array([[1, 2],
           [3, 4]])
    """,
    description: "Create a 2D array"
  }
]
```

## Implementation

### Doc Fetching

```elixir
defmodule SnakeBridge.Docs do
  @cache_table :snakebridge_docs

  def get(module, function, arity \\ nil) do
    key = {module, function, arity}

    case :ets.lookup(@cache_table, key) do
      [{^key, doc}] ->
        doc

      [] ->
        doc = fetch_from_python(module, function, arity)
        :ets.insert(@cache_table, {key, doc})
        doc
    end
  end

  defp fetch_from_python(module, function, _arity) do
    library = module_to_library(module)
    python_name = function_to_python(function)

    script = """
    import #{library}
    import inspect

    obj = getattr(#{library}, '#{python_name}', None)
    if obj:
        doc = inspect.getdoc(obj) or ""
        sig = ""
        try:
            sig = str(inspect.signature(obj))
        except (ValueError, TypeError):
            pass
        print(f"{sig}\\n\\n{doc}")
    else:
        print("Function not found")
    """

    case run_python(script, library) do
      {:ok, output} -> parse_docstring(output)
      {:error, _} -> nil
    end
  end
end
```

### Search Implementation

```elixir
defmodule SnakeBridge.Docs.Search do
  def search(module, query, opts \\ []) do
    library = module_to_library(module)

    # Get function list (cached or quick introspection)
    functions = get_function_list(library)

    # Score each function against query
    scored = functions
    |> Enum.map(fn func ->
      {func, score(func, query, library)}
    end)
    |> Enum.filter(fn {_, score} -> score > 0.3 end)
    |> Enum.sort_by(fn {_, score} -> -score end)
    |> Enum.take(opts[:limit] || 10)

    # Fetch summaries for top results
    Enum.map(scored, fn {func, score} ->
      %{
        name: func,
        signature: get_signature(library, func),
        summary: get_summary(library, func),
        relevance: score
      }
    end)
  end

  defp score(function_name, query, library) do
    name_str = to_string(function_name)
    query_lower = String.downcase(query)
    name_lower = String.downcase(name_str)

    cond do
      # Exact match
      name_lower == query_lower -> 1.0

      # Starts with query
      String.starts_with?(name_lower, query_lower) -> 0.9

      # Contains query
      String.contains?(name_lower, query_lower) -> 0.7

      # Fuzzy match in docstring
      docstring_match?(library, function_name, query) -> 0.5

      # No match
      true -> 0.0
    end
  end

  defp docstring_match?(library, function, query) do
    doc = SnakeBridge.Docs.get_cached_summary(library, function)
    doc && String.contains?(String.downcase(doc), String.downcase(query))
  end
end
```

### IEx Integration

```elixir
defmodule SnakeBridge.IExHelpers do
  @doc """
  Integrate with IEx h/1 helper for seamless doc access.
  """
  def __info__(:docs) do
    # Return documentation in format IEx expects
    {:docs_v1, _anno, _lang, _format, _module_doc, _meta, function_docs}
  end

  # Hook into IEx.Helpers.h/1
  defmacro h({:., _, [module, function]}) when is_atom(function) do
    if snakebridge_module?(module) do
      quote do
        SnakeBridge.Docs.print(unquote(module), unquote(function))
      end
    else
      # Fall back to standard behavior
      quote do
        IEx.Helpers.h(unquote(module).unquote(function))
      end
    end
  end
end
```

## Caching Strategy

### Multi-Level Cache

```
Level 1: ETS (in-memory)
  ├── Hot docs: <1ms access
  ├── Size limit: 1000 entries
  └── Eviction: LRU

Level 2: Disk cache
  ├── All fetched docs
  ├── Size: unlimited
  └── Format: compressed JSON

Level 3: Python (source of truth)
  ├── Always available
  ├── ~50ms per query
  └── Requires library installed
```

### Cache Configuration

```elixir
config :snakebridge,
  docs: [
    # In-memory cache
    memory_cache_size: 1000,
    memory_cache_ttl: :infinity,

    # Disk cache
    disk_cache: true,
    disk_cache_dir: "_build/snakebridge/docs",

    # Prefetch commonly used
    prefetch: [:numpy, :pandas],  # Prefetch function lists on startup
  ]
```

## IDE Integration

### Language Server Protocol

SnakeBridge can provide documentation to LSP-compatible editors:

```elixir
defmodule SnakeBridge.LSP do
  def hover(module, function, _line, _col) do
    if snakebridge_module?(module) do
      doc = SnakeBridge.Docs.get(module, function)
      %{
        contents: %{
          kind: "markdown",
          value: format_for_hover(doc)
        }
      }
    end
  end

  def completion(module, prefix) do
    if snakebridge_module?(module) do
      functions = SnakeBridge.Docs.Search.prefix_match(module, prefix)
      Enum.map(functions, fn {name, summary} ->
        %{
          label: to_string(name),
          kind: :function,
          detail: summary,
          documentation: %{kind: "markdown", value: get_full_doc(module, name)}
        }
      end)
    end
  end
end
```

## Offline Documentation

### Export for Offline Use

```bash
# Export docs for specific libraries
$ mix snakebridge.docs.export numpy pandas --output docs_bundle.json
Exported documentation for 2 libraries (1.2 MB)

# Export all cached docs
$ mix snakebridge.docs.export --all
Exported documentation for 5 libraries (3.5 MB)
```

### Import Offline Docs

```bash
$ mix snakebridge.docs.import docs_bundle.json
Imported 1,500 documentation entries
```

### Static Site Generation

For projects that want traditional static docs:

```bash
# Generate ExDoc-compatible docs for cached functions only
$ mix snakebridge.docs.generate --output doc/python
Generating documentation for 156 cached functions...
Documentation written to doc/python/

# Include in main ExDoc
# mix.exs
docs: [
  extras: ["doc/python/README.md"]
]
```

## Future: Community Documentation

### Crowdsourced Improvements

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Python Docs    │────►│  SnakeBridge    │◄────│   Community     │
│  (upstream)     │     │  Docs Server    │     │   Improvements  │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                              │
                              ▼
                        Better examples,
                        Elixir-specific notes,
                        Type annotations
```

### Example Community Enhancement

```elixir
# Community-contributed Elixir-specific documentation
Numpy.doc(:array, :enhanced)
"""
numpy.array(object, dtype=None, ...)

Create an array.

## Elixir Usage

    iex> Numpy.array([1, 2, 3])
    {:ok, #Numpy.NDArray<[1, 2, 3]>}

    iex> Numpy.array([[1, 2], [3, 4]])
    {:ok, #Numpy.NDArray<[[1, 2], [3, 4]]>}

## Type Mapping

| Python Type | Elixir Type |
|-------------|-------------|
| list → ndarray | list → NDArray reference |
| ndarray → list | NDArray → list (via .tolist()) |

## Common Patterns

    # Create and operate
    {:ok, arr} = Numpy.array([1, 2, 3])
    {:ok, doubled} = Numpy.multiply(arr, 2)

## See Also

- `Numpy.zeros/1` - Create array of zeros
- `Numpy.ones/1` - Create array of ones
"""
```
