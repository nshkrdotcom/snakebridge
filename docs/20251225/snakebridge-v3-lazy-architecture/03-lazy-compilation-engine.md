# Lazy Compilation Engine

## The Core Innovation

The lazy compilation engine detects Python library calls in your source code and generates just-in-time bindings for only those specific functions—BEFORE the Elixir compiler runs.

**Key Insight:** This is a **pre-compilation pass**, not mid-compilation injection. Generated code exists as real `.ex` source files that the Elixir compiler processes normally.

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           mix compile                                     │
│                                                                          │
│   Compilers: [:snakebridge, :elixir, :app]                              │
│              ─────────────                                               │
│                   │                                                      │
│                   │ SnakeBridge runs FIRST                               │
│                   ▼                                                      │
└──────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                    SnakeBridge Compiler Task                             │
│                                                                          │
│   ┌────────────────┐    ┌────────────────┐    ┌────────────────┐        │
│   │  1. AST Scan   │───►│  2. Resolve    │───►│  3. Generate   │        │
│   │  project src   │    │  vs manifest   │    │  missing .ex   │        │
│   └────────────────┘    └────────────────┘    └────────────────┘        │
│                                                       │                  │
│   ┌────────────────┐    ┌────────────────┐           │                  │
│   │  5. Done       │◄───│  4. Update     │◄──────────┘                  │
│   │  (normal elixir│    │  manifest+lock │                              │
│   │   compile next)│    └────────────────┘                              │
│   └────────────────┘                                                     │
└──────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                    Elixir Compiler (normal)                              │
│                                                                          │
│   Compiles lib/*.ex INCLUDING lib/snakebridge_generated/*.ex            │
│   All standard tooling works: Dialyzer, ExDoc, IDE, etc.                │
└──────────────────────────────────────────────────────────────────────────┘
```

## Why Pre-Pass, Not Mid-Injection?

The alternative approach—intercepting undefined function calls during compilation and injecting code on the fly—was rejected because:

| Problem | Pre-Pass Solution |
|---------|-------------------|
| Compilation concurrency races | Files generated before compilation starts |
| Dialyzer sees undefined functions | Generated source exists, normal analysis |
| ExDoc misses generated code | Generated source is normal `.ex` |
| IDE "go to definition" fails | Points to real file in `lib/` |
| Hot code reload confusion | Standard Elixir semantics |
| Complex debugging | Standard Elixir debugging |

**The pre-pass model generates real `.ex` source files that become part of your project.** The Elixir compiler never knows they were generated—they're just more source files to compile.

## Implementation Components

### 1. Mix Compiler Task

The SnakeBridge compiler runs before the Elixir compiler:

```elixir
# mix.exs
def project do
  [
    app: :my_app,
    compilers: [:snakebridge] ++ Mix.compilers(),  # SnakeBridge FIRST
    deps: deps()
  ]
end
```

```elixir
# lib/mix/tasks/compile/snakebridge.ex
defmodule Mix.Tasks.Compile.Snakebridge do
  @moduledoc """
  Scans project for Python library usage and generates bindings.
  Runs before the Elixir compiler.
  """
  use Mix.Task.Compiler

  @impl true
  def run(_args) do
    config = SnakeBridge.Config.load()

    # Skip if no libraries configured
    if config.libraries == [] do
      {:ok, []}
    else
      # 1. Scan project for library calls
      detected = SnakeBridge.Scanner.scan_project()

      # 2. Load current manifest
      manifest = SnakeBridge.Manifest.load()

      # 3. Determine what needs generation
      to_generate = SnakeBridge.Manifest.missing(manifest, detected)

      # 4. Generate source files
      if to_generate != [] do
        SnakeBridge.Generator.generate(to_generate, config)
      end

      # 5. Update manifest and lock
      SnakeBridge.Manifest.update(manifest, detected)
      SnakeBridge.Lock.update()

      {:ok, []}
    end
  end

  @impl true
  def manifests do
    [SnakeBridge.Manifest.path()]
  end
end
```

### 2. AST Scanner

The scanner finds all calls to configured library modules:

```elixir
defmodule SnakeBridge.Scanner do
  @moduledoc """
  Scans project source files for Python library function calls.
  """

  def scan_project do
    source_files()
    |> Enum.flat_map(&scan_file/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp source_files do
    Mix.Project.config()[:elixirc_paths]
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))
    |> Enum.reject(&String.contains?(&1, "snakebridge_generated"))
  end

  defp scan_file(path) do
    {:ok, ast} = path |> File.read!() |> Code.string_to_quoted()
    extract_library_calls(ast)
  end

  defp extract_library_calls(ast) do
    libraries = SnakeBridge.Config.library_modules()

    Macro.prewalk(ast, [], fn
      # Remote call: Numpy.array(x)
      {{:., _, [{:__aliases__, _, module_parts}, function]}, _, args}, acc
      when is_atom(function) and is_list(args) ->
        module = Module.concat(module_parts)
        if module in libraries do
          {ast, [{module, function, length(args)} | acc]}
        else
          {ast, acc}
        end

      # Module attribute that references library
      {:@, _, [{name, _, [{:__aliases__, _, module_parts}]}]}, acc ->
        {ast, acc}

      other, acc ->
        {other, acc}
    end)
    |> elem(1)
  end
end
```

### 3. Python Introspection

Targeted introspection queries only the functions we need:

```elixir
defmodule SnakeBridge.Introspector do
  @moduledoc """
  Introspects Python functions using UV.
  """

  def introspect(library, functions) when is_list(functions) do
    # Batch introspection for efficiency
    script = batch_introspection_script(library, functions)

    case run_python(library, script) do
      {:ok, output} ->
        {:ok, Jason.decode!(output)}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp batch_introspection_script(library, functions) do
    functions_json = Jason.encode!(Enum.map(functions, &to_string/1))

    """
    import #{library.python_name}
    import inspect
    import json

    functions = json.loads('#{functions_json}')
    results = []

    for func_name in functions:
        obj = getattr(#{library.python_name}, func_name, None)
        if obj is None:
            results.append({"name": func_name, "error": "not_found"})
            continue

        try:
            sig = inspect.signature(obj)
            params = [
                {
                    "name": p.name,
                    "kind": str(p.kind),
                    "default": repr(p.default) if p.default != inspect.Parameter.empty else None,
                    "annotation": str(p.annotation) if p.annotation != inspect.Parameter.empty else None
                }
                for p in sig.parameters.values()
            ]
        except (ValueError, TypeError):
            params = []

        doc = inspect.getdoc(obj) or ""

        results.append({
            "name": func_name,
            "parameters": params,
            "docstring": doc[:2000],
            "callable": callable(obj)
        })

    print(json.dumps(results))
    """
  end

  defp run_python(library, script) do
    if library.version == :stdlib do
      case System.cmd("python3", ["-c", script], stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {error, _} -> {:error, error}
      end
    else
      version_spec = "#{library.python_name}#{library.version}"
      case System.cmd("uv", ["run", "--with", version_spec, "python", "-c", script],
             stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {error, _} -> {:error, error}
      end
    end
  end
end
```

### 4. Source Generator

Generates real `.ex` source files:

```elixir
defmodule SnakeBridge.Generator do
  @moduledoc """
  Generates Elixir source files from introspection data.
  """

  @generated_dir "lib/snakebridge_generated"

  def generate(calls_by_library, config) do
    File.mkdir_p!(@generated_dir)

    Enum.each(calls_by_library, fn {library, calls} ->
      # Get function names
      functions = Enum.map(calls, fn {_mod, func, _arity} -> func end)

      # Introspect Python
      {:ok, introspection} = SnakeBridge.Introspector.introspect(library, functions)

      # Generate source
      source = generate_module_source(library, introspection)

      # Write file (sorted, deterministic)
      path = Path.join(@generated_dir, "#{library.name}.ex")
      write_atomic(path, source)

      Mix.shell().info("SnakeBridge: Generated #{path}")
    end)
  end

  defp generate_module_source(library, introspection) do
    functions = introspection
    |> Enum.reject(&Map.has_key?(&1, "error"))
    |> Enum.sort_by(& &1["name"])  # Deterministic order
    |> Enum.map(&generate_function/1)
    |> Enum.join("\n\n")

    """
    # Generated by SnakeBridge - DO NOT EDIT
    # Regenerate with: mix snakebridge.generate
    #
    # Library: #{library.python_name} #{library.version}
    # Generated: #{DateTime.utc_now() |> DateTime.to_iso8601()}

    defmodule #{library.module_name} do
      @moduledoc \"\"\"
      SnakeBridge bindings for #{library.python_name}.

      These functions call Python through the SnakeBridge runtime.
      \"\"\"

      #{functions}
    end
    """
  end

  defp generate_function(info) do
    name = String.to_atom(info["name"])
    params = info["parameters"]
    doc = info["docstring"]

    # Generate parameter list
    param_names = Enum.map(params, fn p -> String.to_atom(p["name"]) end)
    param_vars = Enum.map(param_names, fn n -> Macro.var(n, nil) end)

    """
      @doc \"\"\"
      #{escape_doc(doc)}
      \"\"\"
      def #{name}(#{Enum.join(param_names, ", ")}) do
        SnakeBridge.Runtime.call(__MODULE__, :#{name}, [#{Enum.join(param_names, ", ")}])
      end
    """
  end

  defp escape_doc(doc) do
    doc
    |> String.replace("\"\"\"", "\\\"\\\"\\\"")
    |> String.trim()
  end

  defp write_atomic(path, content) do
    temp_path = path <> ".tmp"
    File.write!(temp_path, content)
    File.rename!(temp_path, path)
  end
end
```

### 5. Manifest and Lock

Track what's been generated for incremental updates:

```elixir
defmodule SnakeBridge.Manifest do
  @manifest_path ".snakebridge/manifest.json"

  defstruct [:version, :generated_at, :symbols]

  def path, do: @manifest_path

  def load do
    case File.read(@manifest_path) do
      {:ok, content} -> Jason.decode!(content, keys: :atoms)
      {:error, :enoent} -> %{version: "3.0.0", symbols: %{}}
    end
  end

  def missing(manifest, detected) do
    existing = Map.keys(manifest.symbols) |> MapSet.new()
    detected_set = MapSet.new(detected, fn {mod, func, arity} ->
      "#{mod}.#{func}/#{arity}"
    end)

    MapSet.difference(detected_set, existing)
    |> MapSet.to_list()
    |> Enum.map(&parse_symbol/1)
  end

  def update(manifest, detected) do
    symbols = Enum.reduce(detected, manifest.symbols, fn {mod, func, arity}, acc ->
      key = "#{mod}.#{func}/#{arity}"
      Map.put_new(acc, key, %{
        generated_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })
    end)

    new_manifest = %{
      version: "3.0.0",
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      symbols: symbols |> Enum.sort() |> Map.new()  # Sorted for determinism
    }

    File.mkdir_p!(Path.dirname(@manifest_path))
    File.write!(@manifest_path, Jason.encode!(new_manifest, pretty: true))
  end
end
```

## Generation Flow

### Step 1: Detection (AST Scan)

```
Developer code:          result = Numpy.dot(a, b)
                                    │
Scanner finds:           {Numpy, :dot, 2}
                                    │
Manifest check:          Numpy.dot/2 in manifest? → No
```

### Step 2: Introspection (Python Query)

```
UV call:                 uv run --with numpy python -c "introspect"
                                    │
Python returns:          {
                           "name": "dot",
                           "parameters": [
                             {"name": "a", "default": null},
                             {"name": "b", "default": null}
                           ],
                           "docstring": "Dot product of two arrays..."
                         }
```

### Step 3: Generation (Source Output)

```elixir
# lib/snakebridge_generated/numpy.ex

defmodule Numpy do
  @moduledoc "SnakeBridge bindings for numpy."

  @doc """
  Dot product of two arrays...
  """
  def dot(a, b) do
    SnakeBridge.Runtime.call(__MODULE__, :dot, [a, b])
  end
end
```

### Step 4: Normal Compilation

```
Elixir compiler:         Compiles lib/snakebridge_generated/numpy.ex
                                    │
Result:                  _build/dev/lib/my_app/ebin/Elixir.Numpy.beam
                                    │
Status:                  Normal compiled module, all tooling works
```

## Performance Characteristics

### First-Time Generation (per library)

| Operation | Time |
|-----------|------|
| AST scanning (all project files) | 50-100ms |
| UV + Python startup | 30-50ms |
| Batch introspection (10 functions) | 50-100ms |
| Source generation | 10-20ms |
| File write | 1-5ms |
| **Total (10 functions)** | **~150-250ms** |

### Incremental (no new functions)

| Operation | Time |
|-----------|------|
| AST scanning | 50-100ms |
| Manifest check | <1ms |
| No generation needed | 0ms |
| **Total** | **~50-100ms** |

### Already Generated (subsequent compiles)

| Operation | Time |
|-----------|------|
| Mix dependency check | ~10ms |
| Manifest unchanged | 0ms |
| **Total** | **~10ms** |

## Batch Optimization

When multiple functions from the same library are detected, they're batched:

```elixir
# Detected calls
[{Numpy, :array, 1}, {Numpy, :zeros, 1}, {Numpy, :dot, 2}]

# Grouped by library
%{numpy_lib => [{Numpy, :array, 1}, {Numpy, :zeros, 1}, {Numpy, :dot, 2}]}

# Single introspection call
introspect(numpy_lib, [:array, :zeros, :dot])

# Result: ~150ms for 3 functions, not 450ms for 3 separate calls
```

## Handling Edge Cases

### Function Not Found in Python

```elixir
# Developer writes:
Numpy.nonexistent_function(x)

# Introspection returns:
{"name": "nonexistent_function", "error": "not_found"}

# Compilation produces warning:
warning: Numpy.nonexistent_function/1 not found in numpy 1.26.4
  lib/my_app.ex:15

# No binding generated, Elixir compiler will error normally
```

### Dynamic Dispatch

```elixir
# Cannot detect this statically:
apply(Numpy, some_var, args)
```

See [11-engineering-decisions.md](./11-engineering-decisions.md#decision-6-dynamic-dispatch-handling) for the runtime ledger solution.

### Circular Imports (Rare)

Circular imports between Python libraries are detected and reported:

```
warning: Circular import detected: scipy -> numpy -> scipy
  Generating stubs; full introspection may fail
```

## File Layout

```
my_app/
├── lib/
│   ├── my_app.ex                 # Your code
│   └── snakebridge_generated/    # Generated code (committed to git)
│       ├── numpy.ex              # All Numpy functions, sorted
│       ├── pandas.ex             # All Pandas functions, sorted
│       └── sympy.ex              # All Sympy functions, sorted
├── .snakebridge/
│   └── manifest.json             # What's been generated
├── snakebridge.lock              # Environment identity + symbols
└── mix.exs
```

## Debugging

### Verbose Mode

```elixir
# config/dev.exs
config :snakebridge, verbose: true
```

```
$ mix compile
SnakeBridge: Scanning 42 source files...
SnakeBridge: Detected 5 library calls
SnakeBridge: Cache hit: Numpy.array/1
SnakeBridge: Cache hit: Numpy.zeros/1
SnakeBridge: Generating: Numpy.reshape/2
SnakeBridge: Introspecting numpy.reshape...
SnakeBridge: Generated lib/snakebridge_generated/numpy.ex
Compiling 1 file (.ex)
```

### Manual Regeneration

```bash
# Force regeneration of all bindings
$ mix snakebridge.generate --force

# Regenerate specific library
$ mix snakebridge.generate numpy

# Clear cache and regenerate
$ rm -rf lib/snakebridge_generated .snakebridge
$ mix compile
```

### Inspection

```elixir
iex> SnakeBridge.Manifest.load()
%{
  version: "3.0.0",
  symbols: %{
    "Numpy.array/1" => %{generated_at: "2025-12-25T10:30:00Z"},
    "Numpy.zeros/1" => %{generated_at: "2025-12-25T10:30:00Z"}
  }
}

iex> SnakeBridge.Lock.environment()
%{
  python_version: "3.11.5",
  platform: "linux-x86_64",
  libraries: %{numpy: "1.26.4"}
}
```
