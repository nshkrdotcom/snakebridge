# Lazy Compilation Engine

## The Core Innovation

The lazy compilation engine intercepts unresolved function calls during compilation, determines if they're Python library calls, and generates just-in-time bindings for only those specific functions.

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           Elixir Compiler                                │
│                                                                          │
│   defmodule MyApp do                                                     │
│     def calc do                                                          │
│       Numpy.array([1,2,3])  ◄──── Unresolved: Numpy.array/1             │
│     end                                                                  │
│   end                                                                    │
└──────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ @on_definition callback
                                    ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                     SnakeBridge.Compiler.Tracer                          │
│                                                                          │
│   1. Detect unresolved remote call to configured library                 │
│   2. Check if Numpy.array/1 exists in cache                              │
│   3. If cached: inject cached module                                     │
│   4. If not: trigger generation pipeline                                 │
└──────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Cache miss
                                    ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                     Generation Pipeline                                   │
│                                                                          │
│   ┌──────────────┐    ┌──────────────┐    ┌──────────────┐              │
│   │  Introspect  │───►│   Generate   │───►│    Cache     │              │
│   │  numpy.array │    │  Numpy.array │    │    Result    │              │
│   └──────────────┘    └──────────────┘    └──────────────┘              │
│                                                                          │
│   Time: ~50-100ms for single function                                    │
└──────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                     Compilation Continues                                 │
│                                                                          │
│   Numpy.array/1 now available, code compiles successfully               │
└──────────────────────────────────────────────────────────────────────────┘
```

## Implementation Components

### 1. Compiler Tracer

The tracer hooks into Elixir's compilation process:

```elixir
defmodule SnakeBridge.Compiler.Tracer do
  @behaviour Mix.Tasks.Compile.Elixir.Tracer

  # Called for every remote function call during compilation
  def trace({:remote_function, meta, module, function, arity}, env) do
    if snakebridge_library?(module) do
      ensure_function_available(module, function, arity, env)
    end
    :ok
  end

  defp snakebridge_library?(module) do
    # Check if module is a configured SnakeBridge library
    SnakeBridge.Registry.library?(module)
  end

  defp ensure_function_available(module, function, arity, env) do
    case SnakeBridge.Cache.get(module, function, arity) do
      {:ok, _} ->
        # Already cached, nothing to do
        :ok

      :not_found ->
        # Generate on demand
        SnakeBridge.Generator.generate_function(module, function, arity)
    end
  end
end
```

### 2. Dynamic Module Injection

When a function is generated, it must be made available to the ongoing compilation:

```elixir
defmodule SnakeBridge.Compiler.Injector do
  @doc """
  Injects a generated function into the compilation environment.
  """
  def inject_function(module, function, arity, ast) do
    # Check if module already exists
    if Code.ensure_loaded?(module) do
      # Module exists, add function via hot code loading
      inject_into_existing(module, function, ast)
    else
      # Module doesn't exist, create minimal module
      create_module_with_function(module, function, ast)
    end
  end

  defp create_module_with_function(module, function, ast) do
    module_ast = quote do
      defmodule unquote(module) do
        use SnakeBridge.LazyModule

        unquote(ast)
      end
    end

    # Compile and load immediately
    Code.compile_quoted(module_ast)
  end

  defp inject_into_existing(module, function, ast) do
    # Use Module.create to add functions dynamically
    # This requires careful handling of module state
    SnakeBridge.DynamicModule.add_function(module, function, ast)
  end
end
```

### 3. Targeted Introspection

Instead of introspecting entire libraries, we query only what's needed:

```elixir
defmodule SnakeBridge.Introspector.Targeted do
  @doc """
  Introspect a single function from a Python library.
  """
  def introspect_function(library, function_name) do
    script = """
    import #{library}
    import inspect
    import json

    func = getattr(#{library}, '#{function_name}', None)
    if func is None:
        print(json.dumps({"error": "not_found"}))
    else:
        sig = inspect.signature(func)
        doc = inspect.getdoc(func) or ""
        params = [
            {"name": p.name, "default": str(p.default) if p.default != inspect.Parameter.empty else None}
            for p in sig.parameters.values()
        ]
        print(json.dumps({
            "name": '#{function_name}',
            "parameters": params,
            "docstring": doc,
            "module": "#{library}"
        }))
    """

    case run_python(script, library) do
      {:ok, json} ->
        Jason.decode!(json)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_python(script, library) do
    # Use UV for non-stdlib libraries
    if SnakeBridge.Registry.stdlib?(library) do
      System.cmd("python3", ["-c", script])
    else
      version = SnakeBridge.Registry.version(library)
      System.cmd("uv", ["run", "--with", "#{library}#{version}", "python", "-c", script])
    end
  end
end
```

### 4. Lazy Module Base

Generated modules include lazy-loading infrastructure:

```elixir
defmodule SnakeBridge.LazyModule do
  @moduledoc """
  Base module for lazily-generated library bindings.
  """

  defmacro __using__(_opts) do
    quote do
      @before_compile SnakeBridge.LazyModule

      # Track which functions are defined
      Module.register_attribute(__MODULE__, :snakebridge_functions, accumulate: true)

      # Allow dynamic function addition
      def __snakebridge_add_function__(name, arity, ast) do
        SnakeBridge.DynamicModule.add_function(__MODULE__, name, arity, ast)
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      # Generate __functions__ discovery at compile time
      def __functions__ do
        @snakebridge_functions
        |> Enum.map(fn {name, arity} ->
          {name, arity, __MODULE__, doc_for(name, arity)}
        end)
      end

      defp doc_for(name, arity) do
        SnakeBridge.Docs.get(__MODULE__, name, arity)
      end
    end
  end
end
```

## Generation Flow

### Step 1: Detection

```
Developer code:          result = Numpy.dot(a, b)
                                    │
Compiler sees:           Numpy.dot/2 (unresolved)
                                    │
Tracer checks:           Is Numpy a SnakeBridge library? → Yes
                                    │
Cache lookup:            Numpy.dot/2 cached? → No
```

### Step 2: Introspection

```
UV call:                 uv run --with numpy python -c "introspect numpy.dot"
                                    │
Python returns:          {
                           "name": "dot",
                           "parameters": [
                             {"name": "a", "default": null},
                             {"name": "b", "default": null}
                           ],
                           "docstring": "Dot product of two arrays...",
                           "return_type": "ndarray"
                         }
```

### Step 3: Generation

```elixir
# Generated AST
quote do
  @doc """
  Dot product of two arrays...

  ## Parameters
    * `a` - First array
    * `b` - Second array
  """
  @spec dot(any(), any()) :: {:ok, any()} | {:error, term()}
  def dot(a, b) do
    SnakeBridge.Runtime.call("numpy", "dot", [a, b])
  end
end
```

### Step 4: Injection & Caching

```
1. AST compiled to BEAM bytecode
2. Module Numpy loaded/updated with new function
3. Cache entry created:
   - Key: {Numpy, :dot, 2}
   - Value: {ast, bytecode, introspection_data}
   - Metadata: {generated_at, source_version}
4. Compilation continues
```

## Performance Characteristics

### First-Time Generation

| Operation | Time |
|-----------|------|
| UV + Python startup | 30-50ms |
| Introspection | 10-20ms |
| Code generation | 5-10ms |
| Compilation | 10-20ms |
| Cache write | 1-5ms |
| **Total** | **~50-100ms** |

### Cached Function

| Operation | Time |
|-----------|------|
| Cache lookup | <1ms |
| Module injection | 1-5ms |
| **Total** | **~5ms** |

### Batch Generation

When multiple functions are detected in a single file:

```elixir
# This file uses 5 numpy functions
Numpy.array(...)
Numpy.zeros(...)
Numpy.dot(...)
Numpy.sum(...)
Numpy.reshape(...)
```

The engine batches these into a single introspection call:

```
UV call:    uv run --with numpy python -c "introspect_batch numpy [array, zeros, dot, sum, reshape]"
Time:       ~100ms (vs. 500ms for 5 separate calls)
```

## Edge Cases

### Function Not Found

```elixir
# Developer writes:
Numpy.nonexistent_function(x)

# Introspection returns:
{"error": "not_found"}

# Compiler produces:
** (CompileError) undefined function Numpy.nonexistent_function/1
   Hint: This function does not exist in numpy 1.26.4
```

### Version Mismatch

```elixir
# numpy 2.0 removed oldfunction
Numpy.oldfunction(x)

# Detection:
warning: Numpy.oldfunction/1 not found in numpy 2.0.0
         This function may have been removed or renamed.
         See: https://numpy.org/doc/stable/release/2.0.0-notes.html
```

### Circular Dependencies

Rare but possible when Python modules cross-reference:

```
scipy.stats uses numpy
numpy.polynomial uses scipy (hypothetically)
```

The engine detects cycles and generates stubs:

```elixir
# Stub generated first
defmodule Numpy.Polynomial do
  def problematic_function(x), do: raise "Circular dependency detected"
end

# Then replaced with real implementation after resolution
```

## Compiler Integration

### Mix Compiler Hook

```elixir
# lib/mix/tasks/compile/snakebridge.ex
defmodule Mix.Tasks.Compile.Snakebridge do
  use Mix.Task.Compiler

  def run(_args) do
    # Register the tracer
    Mix.Task.Compiler.after_compiler(:elixir, &after_elixir_compile/1)

    # Initialize cache
    SnakeBridge.Cache.init()

    # Pre-create module stubs for configured libraries
    for {library, _opts} <- SnakeBridge.Config.libraries() do
      SnakeBridge.ModuleStub.create(library)
    end

    {:ok, []}
  end

  defp after_elixir_compile(status) do
    # Report what was generated
    generated = SnakeBridge.Cache.new_this_compile()
    if generated != [] do
      IO.puts("SnakeBridge: Generated #{length(generated)} bindings")
    end
    status
  end
end
```

### Module Stubs

Before compilation, we create minimal stubs so the compiler knows these modules exist:

```elixir
defmodule SnakeBridge.ModuleStub do
  def create(library) do
    module_name = SnakeBridge.Config.module_name(library)

    unless Code.ensure_loaded?(module_name) do
      # Create empty module with __missing__ handler
      Code.compile_quoted(quote do
        defmodule unquote(module_name) do
          use SnakeBridge.LazyModule

          # Fallback for any undefined function
          def unquote(:__missing__)(function, args) do
            SnakeBridge.Generator.generate_and_call(
              unquote(module_name),
              function,
              args
            )
          end
        end
      end)
    end
  end
end
```

## Debugging

### Verbose Mode

```elixir
config :snakebridge, verbose: true
```

Output:
```
[SnakeBridge] Cache miss: Numpy.array/1
[SnakeBridge] Introspecting numpy.array...
[SnakeBridge] Generated Numpy.array/1 in 87ms
[SnakeBridge] Cache hit: Numpy.zeros/1
[SnakeBridge] Compilation complete. Generated: 1, Cached: 1
```

### Inspection

```elixir
# IEx
iex> SnakeBridge.Cache.stats()
%{
  hits: 45,
  misses: 3,
  total_entries: 48,
  libraries: %{
    Numpy: 35,
    Pandas: 10,
    Json: 3
  }
}

iex> SnakeBridge.Cache.list(Numpy)
[
  {:array, 1, ~U[2025-12-25 10:30:00Z]},
  {:zeros, 2, ~U[2025-12-25 10:30:05Z]},
  ...
]
```

## Future Optimizations

### 1. Parallel Introspection

When multiple libraries are used, introspect concurrently:

```elixir
Task.async_stream(libraries, &introspect/1, max_concurrency: 4)
```

### 2. Persistent Python Process

Keep a Python process warm for faster introspection:

```
First call:   100ms (cold start)
Subsequent:   10-20ms (warm)
```

### 3. Predictive Generation

Analyze import patterns to predict what will be needed:

```elixir
# If developer uses Numpy.array, they probably need:
# - Numpy.zeros
# - Numpy.ones
# - Numpy.reshape
# Pre-generate in background
```

### 4. Shared Team Cache

Fetch pre-generated bindings from team server:

```
Developer A generates Numpy.array/1
             │
             ▼
      Team Cache Server
             │
             ▼
Developer B gets instant cache hit
```
