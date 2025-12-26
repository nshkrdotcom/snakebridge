# AST Scanner

## Purpose

The scanner walks your project source files and extracts all calls to configured Python library modules. This enables **lazy generation**—only generate bindings for functions you actually use.

## How It Works

```
lib/my_app/analysis.ex            Scanner              Detected Symbols
┌─────────────────────────┐      ┌──────────┐         ┌──────────────────┐
│ defmodule MyApp.Analysis│      │          │         │                  │
│   def run(data) do      │      │  1. Walk │         │ {Numpy, :array, 1│
│     Numpy.array(data)   │─────►│     AST  │────────►│ {Numpy, :mean, 1}│
│     Numpy.mean(arr)     │      │          │         │ {Numpy, :std, 1} │
│   end                   │      │ 2. Match │         │                  │
│ end                     │      │    calls │         │                  │
└─────────────────────────┘      └──────────┘         └──────────────────┘
```

## What It Detects

### Direct Module Calls

```elixir
Numpy.array([1, 2, 3])
# → {Numpy, :array, 1}
```

### Aliased Modules

```elixir
alias Numpy, as: Np
Np.zeros({10, 10})
# → {Numpy, :zeros, 1}
```

### Imported Functions

```elixir
import Numpy, only: [array: 1]
array([1, 2, 3])
# → {Numpy, :array, 1}
```

### Submodules

```elixir
Numpy.Linalg.solve(a, b)
# → {Numpy.Linalg, :solve, 2}
```

### Chained Calls

```elixir
data
|> Numpy.array()
|> Numpy.reshape({2, 3})
# → {Numpy, :array, 1}, {Numpy, :reshape, 2}
```

## What It Does NOT Detect

### Dynamic Dispatch

```elixir
func = :array
apply(Numpy, func, [[1, 2, 3]])
# NOT detected - use ledger for this
```

### String-Based Calls

```elixir
module = Module.concat(Numpy, :Linalg)
apply(module, :solve, [a, b])
# NOT detected - use ledger for this
```

### Runtime-Computed Modules

```elixir
{:ok, mod} = get_library()
mod.process(data)
# NOT detected
```

Dynamic calls are handled via the **ledger system**. See [05-cache-manifest.md](05-cache-manifest.md).

## Implementation

```elixir
defmodule SnakeBridge.Scanner do
  @moduledoc """
  Scans project source for Python library function calls.
  """

  @doc """
  Scan all project source files for library calls.
  Returns a list of {module, function, arity} tuples.
  """
  def scan_project(config) do
    library_modules = config.libraries |> Enum.map(& &1.module_name)
    
    source_files(config)
    |> Task.async_stream(&scan_file(&1, library_modules), ordered: false)
    |> Enum.flat_map(fn {:ok, calls} -> calls end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp source_files(config) do
    scan_paths = config.scan_paths || ["lib"]
    scan_exclude = config.scan_exclude || []
    
    scan_paths
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))
    |> Enum.reject(&in_generated_dir?(&1, config))
    |> Enum.reject(&excluded_path?(&1, scan_exclude))
  end

  defp in_generated_dir?(path, config) do
    String.starts_with?(path, config.generated_dir)
  end

  defp excluded_path?(path, patterns) do
    Enum.any?(patterns, fn pattern ->
      Path.wildcard(pattern) |> Enum.member?(path)
    end)
  end

  defp scan_file(path, library_modules) do
    content = File.read!(path)
    
    case Code.string_to_quoted(content, file: path) do
      {:ok, ast} ->
        context = build_context(ast, library_modules)
        extract_calls(ast, context)
      {:error, _} ->
        []  # Skip files with syntax errors
    end
  end

  defp build_context(ast, library_modules) do
    # Extract alias and import statements
    {_, context} = Macro.prewalk(ast, %{aliases: %{}, imports: []}, fn
      {:alias, _, [{:__aliases__, _, parts} | opts]}, ctx ->
        module = Module.concat(parts)
        if module in library_modules do
          alias_name = get_alias_name(parts, opts)
          {nil, put_in(ctx, [:aliases, alias_name], module)}
        else
          {nil, ctx}
        end

      {:import, _, [{:__aliases__, _, parts} | opts]}, ctx ->
        module = Module.concat(parts)
        if module in library_modules do
          {nil, update_in(ctx, [:imports], &[{module, opts} | &1])}
        else
          {nil, ctx}
        end

      node, ctx ->
        {node, ctx}
    end)

    Map.put(context, :library_modules, library_modules)
  end

  defp get_alias_name(parts, opts) do
    case Keyword.get(opts, :as) do
      {:__aliases__, _, [name]} -> name
      nil -> List.last(parts)
    end
  end

  defp extract_calls(ast, context) do
    {_, calls} = Macro.prewalk(ast, [], fn
      # Remote call: Numpy.array(x) or Np.array(x)
      {{:., _, [{:__aliases__, _, parts}, function]}, _, args}, acc
      when is_atom(function) and is_list(args) ->
        module = resolve_module(parts, context)
        if module do
          {nil, [{module, function, length(args)} | acc]}
        else
          {nil, acc}
        end

      # Imported call: array(x) when import Numpy, only: [array: 1]
      {function, _, args}, acc
      when is_atom(function) and is_list(args) ->
        case find_import(function, length(args), context) do
          {:ok, module} -> {nil, [{module, function, length(args)} | acc]}
          :not_found -> {nil, acc}
        end

      node, acc ->
        {node, acc}
    end)

    calls
  end

  defp resolve_module(parts, context) do
    # Try as alias first
    case parts do
      [name] when is_atom(name) ->
        Map.get(context.aliases, name)
      _ ->
        # Try as direct module
        module = Module.concat(parts)
        if module in context.library_modules, do: module, else: nil
    end
  end

  defp find_import(function, arity, context) do
    Enum.find_value(context.imports, :not_found, fn {module, opts} ->
      only = Keyword.get(opts, :only, nil)
      except = Keyword.get(opts, :except, [])
      
      cond do
        {function, arity} in except -> nil
        only && {function, arity} not in only -> nil
        true -> {:ok, module}
      end
    end)
  end
end
```

## Configuration

```elixir
config :snakebridge,
  # Paths to scan for library usage
  scan_paths: ["lib"],
  
  # Patterns to exclude
  scan_exclude: ["lib/my_app/legacy/**"]
```

## Performance

The scanner is designed for incremental builds:

| Scenario | Behavior |
|----------|----------|
| First compile | Full scan of all source files |
| Incremental (no changes) | Skip scan (use cached manifest) |
| Incremental (file changed) | Rescan changed files only |

Scan time scales with project size:
- 100 files: ~50ms
- 1000 files: ~500ms
- 10000 files: ~5s

Incremental scanning uses a simple file-hash cache in `.snakebridge/scan_cache.json`. If the cache is missing, a full scan runs.

## Error Handling

- **Syntax errors**: files with parse errors are skipped with a warning.
- **Missing files**: ignored; scan is best-effort.
- **Unsupported AST**: ignored; no crash.

In strict mode, scanner errors are surfaced as compiler diagnostics rather than silent skips.

## Debugging

```bash
$ mix snakebridge.scan --verbose
Scanning lib/ for library calls...
  lib/my_app/analysis.ex:
    - Numpy.array/1 (line 5)
    - Numpy.mean/1 (line 6)
    - Numpy.std/1 (line 7)
  lib/my_app/ml.ex:
    - Numpy.zeros/2 (line 10)
    - Pandas.DataFrame/1 (line 15)

Total: 5 unique symbols in 2 files
```

## Edge Cases

### Macro-Generated Calls

```elixir
defmacro with_numpy(do: block) do
  quote do
    Numpy.array(unquote(block))
  end
end
```

Macro-generated calls are **not** detected. The scanner operates on source AST before compilation and does not expand macros. If you rely on macros to emit library calls, use one of:

- `libraries: [numpy: [include: ["array"]]]` in `mix.exs`
- `mix snakebridge.generate --from lib/` to force scan+generate
- Ledger promotion for runtime dynamic usage

### Protocol Implementations

```elixir
defimpl MyProtocol, for: Numpy.NDArray do
  def process(arr), do: Numpy.sum(arr)
end
```

Detected normally—protocol impls are just modules.

### Quote Blocks (Not Executed)

```elixir
quote do
  Numpy.array([1, 2, 3])
end
```

**Not detected**. Quote blocks are AST literals, not function calls. If you need this, use explicit generation:

```elixir
libraries: [
  numpy: [include: ["array"]]
]
```
