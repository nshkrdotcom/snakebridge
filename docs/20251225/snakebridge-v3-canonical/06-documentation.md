# Documentation System

## Philosophy

Instead of generating complete static documentation for every function (expensive, mostly unread), v3 treats documentation as a **queryable data source**. Docs are fetched on demand and cached.

```
Traditional:  Generate all docs → Build static site → Search locally
v3 Approach:  Query on demand → Return answer → Cache for speed
```

## API

### Function Documentation

```elixir
# Get documentation for a specific function
iex> Numpy.doc(:array)
"""
numpy.array(object, dtype=None, *, copy=True, order='K', subok=False, ndmin=0)

Create an array.

Parameters
----------
object : array_like
    An array, any object exposing the array interface, or any sequence.
dtype : data-type, optional
    The desired data-type for the array.
...
"""

# Works with IEx helper too
iex> h Numpy.array
# (same output, formatted for terminal)
```

### Search

```elixir
iex> Numpy.search("matrix multiply")
[
  %{name: :matmul, summary: "Matrix product of two arrays.", relevance: 0.95},
  %{name: :dot, summary: "Dot product of two arrays.", relevance: 0.87},
  %{name: :multiply, summary: "Multiply arguments element-wise.", relevance: 0.72}
]
```

### Discovery

```elixir
iex> Numpy.__functions__()
[
  {:array, 1, Numpy, "Create an array."},
  {:mean, 1, Numpy, "Compute the arithmetic mean..."},
  {:std, 1, Numpy, "Compute the standard deviation..."}
]

iex> Numpy.__functions__() |> Enum.take(3)
# Quick preview
```

## Implementation

### Doc Fetching

```elixir
defmodule SnakeBridge.Docs do
  @moduledoc """
  On-demand documentation fetching with caching.
  """

  @cache_table :snakebridge_docs

  def get(module, function) do
    key = {module, function}
    
    case :ets.lookup(@cache_table, key) do
      [{^key, doc}] ->
        doc
        
      [] ->
        doc = fetch_from_python(module, function)
        :ets.insert(@cache_table, {key, doc})
        doc
    end
  end

  def search(module, query) do
    library = module_to_library(module)
    functions = get_function_list(library)
    
    functions
    |> Enum.map(&{&1, score(&1, query)})
    |> Enum.filter(fn {_, score} -> score > 0.3 end)
    |> Enum.sort_by(fn {_, score} -> -score end)
    |> Enum.take(10)
    |> Enum.map(fn {func, score} ->
      %{name: func, summary: get_summary(library, func), relevance: score}
    end)
  end

  defp fetch_from_python(module, function) do
    library = module_to_library(module)
    
    script = """
    import #{library.python_name}
    import inspect
    obj = getattr(#{library.python_name}, '#{function}', None)
    if obj:
        print(inspect.getdoc(obj) or "No documentation available.")
    else:
        print("Function not found.")
    """
    
    case run_python(library, script) do
      {:ok, output} -> String.trim(output)
      {:error, _} -> "Documentation unavailable."
    end
  end

  defp score(function_name, query) do
    name = to_string(function_name) |> String.downcase()
    query = String.downcase(query)
    
    cond do
      name == query -> 1.0
      String.starts_with?(name, query) -> 0.9
      String.contains?(name, query) -> 0.7
      true -> 0.0
    end
  end
end
```

### Caching Strategy

```
Level 1: ETS (in-memory)
  ├── Hot docs accessed this session
  ├── Instant access (<1ms)
  └── Cleared on restart

Level 2: Python (source of truth)
  ├── Always accurate to installed version
  ├── ~50ms per query
  └── Requires Python available
```

## IEx Integration

```elixir
defmodule SnakeBridge.IExHelpers do
  @moduledoc """
  IEx integration for documentation.
  """

  def print_doc(module, function) do
    doc = SnakeBridge.Docs.get(module, function)
    
    IO.puts(IO.ANSI.cyan() <> "#{module}.#{function}" <> IO.ANSI.reset())
    IO.puts("")
    IO.puts(doc)
  end
end
```

The generated modules include discovery functions that delegate to the docs system:

```elixir
defmodule Numpy do
  # ... generated functions ...

  @doc false
  def doc(function), do: SnakeBridge.Docs.get(__MODULE__, function)
  
  @doc false  
  def __search__(query), do: SnakeBridge.Docs.search(__MODULE__, query)
end
```

## RST to Markdown Conversion

Python docstrings are typically reStructuredText (RST), not Markdown. For rendering in Elixir tools:

```elixir
defmodule SnakeBridge.Docs.Formatter do
  @moduledoc """
  Converts Python RST docstrings to Markdown.
  """

  def to_markdown(rst_doc) do
    rst_doc
    |> convert_parameters_section()
    |> convert_returns_section()
    |> convert_code_blocks()
    |> convert_references()
  end

  defp convert_parameters_section(doc) do
    # RST: Parameters\n----------\nparam : type\n    Description
    # MD:  ## Parameters\n\n- `param` (type) - Description
    
    Regex.replace(~r/Parameters\n-+\n(.+?)(?=\n\n|\z)/s, doc, fn _, params ->
      "## Parameters\n\n" <> format_params(params)
    end)
  end

  defp convert_code_blocks(doc) do
    # RST: >>> code
    # MD:  ```python\ncode\n```
    
    Regex.replace(~r/>>> (.+)/m, doc, fn _, code ->
      "```python\n#{code}\n```"
    end)
  end
end
```

## IDE Integration

### Hover Documentation

When configured, IDEs can query documentation via LSP:

```elixir
defmodule SnakeBridge.LSP do
  def hover(module, function, _line, _col) do
    if snakebridge_module?(module) do
      doc = SnakeBridge.Docs.get(module, function)
      %{
        contents: %{
          kind: "markdown",
          value: SnakeBridge.Docs.Formatter.to_markdown(doc)
        }
      }
    end
  end
end
```

### Autocomplete

```elixir
def completions(module, prefix) do
  if snakebridge_module?(module) do
    module.__functions__()
    |> Enum.filter(fn {name, _, _, _} ->
      String.starts_with?(to_string(name), prefix)
    end)
    |> Enum.map(fn {name, arity, _, summary} ->
      %{label: "#{name}/#{arity}", detail: summary}
    end)
  end
end
```

## Performance

| Operation | Time |
|-----------|------|
| Cached doc lookup | <1ms |
| Python doc fetch | ~50ms |
| Search (100 functions) | <10ms |
| Full function list | <1ms |

First access is slower (Python query), subsequent accesses are instant (ETS cache).

## Configuration

```elixir
config :snakebridge,
  docs: [
    # Enable caching
    cache_enabled: true,
    
    # Cache TTL (infinity = never expire)
    cache_ttl: :infinity,
    
    # Source: :python (always accurate) or :metadata (faster, may be stale)
    source: :python,
    
    # Convert RST to Markdown
    format: :markdown
  ]
```
