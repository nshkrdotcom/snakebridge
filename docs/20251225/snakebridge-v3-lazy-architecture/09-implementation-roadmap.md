# Implementation Roadmap

## Overview

This document outlines the technical implementation plan for SnakeBridge v3. The work is organized into phases, with each phase delivering a working increment.

## Phase 0: Foundation Cleanup

**Goal: Clean slate for v3 development**

### 0.1 Archive v2 Code

```bash
# Already done
git mv lib/snakebridge lib/snakebridge_v2_archived
git mv test/snakebridge test/snakebridge_v2_archived
```

### 0.2 Minimal Project Structure

```
lib/
├── snakebridge.ex                    # Public API
├── snakebridge/
│   ├── config.ex                     # Configuration parsing
│   ├── registry.ex                   # Library registration
│   ├── compiler/
│   │   ├── tracer.ex                # Compilation tracer
│   │   ├── injector.ex              # Module injection
│   │   └── stub.ex                  # Module stubs
│   ├── generator/
│   │   ├── introspector.ex          # Python introspection
│   │   ├── code_gen.ex              # Elixir code generation
│   │   └── batch.ex                 # Batch generation
│   ├── cache/
│   │   ├── manifest.ex              # Cache manifest
│   │   ├── store.ex                 # Disk storage
│   │   └── stats.ex                 # Usage tracking
│   ├── runtime/
│   │   ├── caller.ex                # Python call interface
│   │   └── pool.ex                  # UV process pool
│   └── docs/
│       ├── fetcher.ex               # Doc fetching
│       └── cache.ex                 # Doc caching
├── mix/
│   └── tasks/
│       ├── snakebridge.analyze.ex
│       ├── snakebridge.prune.ex
│       └── snakebridge.cache.ex
test/
├── snakebridge/
│   ├── config_test.exs
│   ├── compiler_test.exs
│   ├── generator_test.exs
│   ├── cache_test.exs
│   └── runtime_test.exs
└── integration/
    ├── numpy_test.exs
    └── stdlib_test.exs
```

### 0.3 Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:jason, "~> 1.4"},           # JSON parsing
    {:telemetry, "~> 1.0"},       # Metrics
    {:file_system, "~> 1.0"},     # File watching (dev)
    # No external Python dependencies - UV handles all
  ]
end
```

## Phase 1: Configuration System

**Goal: Parse library configuration from mix.exs**

### 1.1 Configuration Parsing

```elixir
# lib/snakebridge/config.ex
defmodule SnakeBridge.Config do
  @moduledoc """
  Parses and validates SnakeBridge configuration from mix.exs.
  """

  defstruct [
    :libraries,
    :cache_dir,
    :lazy,
    :verbose
  ]

  @type library_config :: %{
    name: atom(),
    version: String.t() | :stdlib,
    module_name: module(),
    prune: :manual | :auto,
    prune_keep_days: non_neg_integer()
  }

  def parse(opts) do
    libraries = parse_libraries(opts[:libraries] || [])
    %__MODULE__{
      libraries: libraries,
      cache_dir: opts[:cache_dir] || "_build/snakebridge",
      lazy: Keyword.get(opts, :lazy, true),
      verbose: Keyword.get(opts, :verbose, false)
    }
  end

  defp parse_libraries(libs) do
    Enum.map(libs, &parse_library/1)
  end

  defp parse_library({name, :stdlib}) do
    %{name: name, version: :stdlib, module_name: module_name(name)}
  end

  defp parse_library({name, version}) when is_binary(version) do
    %{name: name, version: version, module_name: module_name(name)}
  end

  defp parse_library({name, opts}) when is_list(opts) do
    %{
      name: name,
      version: opts[:version],
      module_name: opts[:module_name] || module_name(name),
      prune: opts[:prune] || :manual,
      prune_keep_days: opts[:prune_keep_days] || 30
    }
  end

  defp module_name(lib_name) do
    lib_name
    |> to_string()
    |> Macro.camelize()
    |> String.to_atom()
  end
end
```

### 1.2 Registry

```elixir
# lib/snakebridge/registry.ex
defmodule SnakeBridge.Registry do
  @moduledoc """
  Registry of configured Python libraries.
  """

  use GenServer

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def library?(module) do
    GenServer.call(__MODULE__, {:library?, module})
  end

  def get_library(module) do
    GenServer.call(__MODULE__, {:get_library, module})
  end

  def libraries do
    GenServer.call(__MODULE__, :libraries)
  end

  # GenServer callbacks
  def init(config) do
    table = :ets.new(:snakebridge_registry, [:set, :protected])
    Enum.each(config.libraries, fn lib ->
      :ets.insert(table, {lib.module_name, lib})
    end)
    {:ok, %{table: table, config: config}}
  end

  def handle_call({:library?, module}, _from, state) do
    result = :ets.member(state.table, module)
    {:reply, result, state}
  end

  def handle_call({:get_library, module}, _from, state) do
    case :ets.lookup(state.table, module) do
      [{^module, lib}] -> {:reply, {:ok, lib}, state}
      [] -> {:reply, :error, state}
    end
  end

  def handle_call(:libraries, _from, state) do
    libs = :ets.tab2list(state.table) |> Enum.map(fn {_, lib} -> lib end)
    {:reply, libs, state}
  end
end
```

### 1.3 Tests

```elixir
# test/snakebridge/config_test.exs
defmodule SnakeBridge.ConfigTest do
  use ExUnit.Case

  alias SnakeBridge.Config

  test "parses simple version string" do
    config = Config.parse(libraries: [numpy: "~> 1.26"])

    assert [lib] = config.libraries
    assert lib.name == :numpy
    assert lib.version == "~> 1.26"
    assert lib.module_name == Numpy
  end

  test "parses stdlib" do
    config = Config.parse(libraries: [json: :stdlib])

    assert [lib] = config.libraries
    assert lib.name == :json
    assert lib.version == :stdlib
  end

  test "parses options" do
    config = Config.parse(libraries: [
      numpy: [version: "~> 1.26", module_name: Np, prune: :auto]
    ])

    assert [lib] = config.libraries
    assert lib.module_name == Np
    assert lib.prune == :auto
  end
end
```

## Phase 2: Compiler Integration

**Goal: Detect unresolved Python calls during compilation**

### 2.1 Compiler Tracer

```elixir
# lib/snakebridge/compiler/tracer.ex
defmodule SnakeBridge.Compiler.Tracer do
  @moduledoc """
  Traces Elixir compilation to detect SnakeBridge library calls.
  """

  @behaviour Mix.Tasks.Compile.Elixir.Tracer

  def trace({:remote_function, _meta, module, function, arity}, env) do
    if SnakeBridge.Registry.library?(module) do
      handle_library_call(module, function, arity, env)
    end
    :ok
  end

  def trace(_event, _env), do: :ok

  defp handle_library_call(module, function, arity, _env) do
    case SnakeBridge.Cache.get(module, function, arity) do
      {:ok, _bytecode} ->
        # Already cached, ensure loaded
        SnakeBridge.Compiler.Injector.ensure_loaded(module, function, arity)

      :not_found ->
        # Queue for generation
        SnakeBridge.Generator.queue(module, function, arity)
    end
  end
end
```

### 2.2 Module Stubs

```elixir
# lib/snakebridge/compiler/stub.ex
defmodule SnakeBridge.Compiler.Stub do
  @moduledoc """
  Creates minimal module stubs so compiler recognizes library modules.
  """

  def create_stubs(libraries) do
    Enum.each(libraries, &create_stub/1)
  end

  def create_stub(library) do
    module = library.module_name

    unless Code.ensure_loaded?(module) do
      contents = quote do
        @moduledoc """
        SnakeBridge bindings for #{unquote(library.name)}.

        Functions are generated on demand during compilation.
        """

        def __snakebridge_library__, do: unquote(library.name)
        def __snakebridge_version__, do: unquote(library.version)
      end

      Module.create(module, contents, Macro.Env.location(__ENV__))
    end
  end
end
```

### 2.3 Mix Compiler

```elixir
# lib/mix/tasks/compile/snakebridge.ex
defmodule Mix.Tasks.Compile.Snakebridge do
  @moduledoc """
  SnakeBridge compiler that runs before Elixir compiler.
  """

  use Mix.Task.Compiler

  @impl true
  def run(_args) do
    # Get configuration from mix.exs
    config = get_snakebridge_config()

    # Start registry
    SnakeBridge.Registry.start_link(config)

    # Create module stubs
    SnakeBridge.Compiler.Stub.create_stubs(config.libraries)

    # Initialize cache
    SnakeBridge.Cache.init(config.cache_dir)

    # Register tracer
    Mix.Tasks.Compile.Elixir.run(["--tracer", "SnakeBridge.Compiler.Tracer"])

    # Process generation queue
    generated = SnakeBridge.Generator.process_queue()

    if config.verbose and generated > 0 do
      Mix.shell().info("SnakeBridge: Generated #{generated} bindings")
    end

    {:ok, []}
  end

  defp get_snakebridge_config do
    deps = Mix.Project.config()[:deps] || []

    case Enum.find(deps, fn {name, _} -> name == :snakebridge end) do
      {_, opts} when is_list(opts) ->
        SnakeBridge.Config.parse(opts)
      _ ->
        SnakeBridge.Config.parse([])
    end
  end
end
```

## Phase 3: Introspection & Generation

**Goal: Generate Elixir bindings from Python introspection**

### 3.1 Targeted Introspection

```elixir
# lib/snakebridge/generator/introspector.ex
defmodule SnakeBridge.Generator.Introspector do
  @moduledoc """
  Introspects Python functions using UV.
  """

  def introspect(library, function) do
    script = introspection_script(library, function)

    case run_python(library, script) do
      {:ok, output} ->
        {:ok, Jason.decode!(output)}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def introspect_batch(library, functions) do
    script = batch_introspection_script(library, functions)

    case run_python(library, script) do
      {:ok, output} ->
        {:ok, Jason.decode!(output)}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp introspection_script(library, function) do
    """
    import #{library}
    import inspect
    import json

    obj = getattr(#{library}, '#{function}', None)
    if obj is None:
        print(json.dumps({"error": "not_found", "function": "#{function}"}))
    else:
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

        print(json.dumps({
            "name": "#{function}",
            "parameters": params,
            "docstring": doc[:2000],  # Truncate long docs
            "module": "#{library}",
            "type": "function" if callable(obj) else "constant"
        }))
    """
  end

  defp run_python(library, script) do
    if library.version == :stdlib do
      System.cmd("python3", ["-c", script], stderr_to_stdout: true)
    else
      version_spec = "#{library.name}#{library.version}"
      System.cmd("uv", ["run", "--with", version_spec, "python", "-c", script],
        stderr_to_stdout: true)
    end
    |> case do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end
end
```

### 3.2 Code Generation

```elixir
# lib/snakebridge/generator/code_gen.ex
defmodule SnakeBridge.Generator.CodeGen do
  @moduledoc """
  Generates Elixir function definitions from introspection data.
  """

  def generate_function(module, introspection) do
    function_name = String.to_atom(introspection["name"])
    params = introspection["parameters"]
    docstring = introspection["docstring"]
    library = introspection["module"]

    # Generate parameter list
    {required, optional} = split_params(params)
    arity = length(required)

    # Generate function AST
    ast = quote do
      @doc unquote(format_doc(docstring, params))
      def unquote(function_name)(unquote_splicing(param_vars(required))) do
        SnakeBridge.Runtime.call(
          unquote(library),
          unquote(to_string(function_name)),
          unquote(param_vars(required))
        )
      end
    end

    # Add optional parameter variants
    optional_asts = generate_optional_variants(function_name, required, optional, library)

    {function_name, arity, [ast | optional_asts]}
  end

  defp split_params(params) do
    Enum.split_with(params, fn p -> p["default"] == nil end)
  end

  defp param_vars(params) do
    Enum.map(params, fn p ->
      name = String.to_atom(p["name"])
      Macro.var(name, nil)
    end)
  end

  defp format_doc(docstring, params) do
    param_docs = Enum.map(params, fn p ->
      "  * `#{p["name"]}` - #{p["annotation"] || "any"}"
    end)

    """
    #{docstring}

    ## Parameters

    #{Enum.join(param_docs, "\n")}
    """
  end

  defp generate_optional_variants(function_name, required, optional, library) do
    # Generate function clauses with default params
    # This creates Numpy.array/1, Numpy.array/2, etc.
    Enum.flat_map(1..length(optional), fn n ->
      opts = Enum.take(optional, n)
      all_params = required ++ opts

      [quote do
        def unquote(function_name)(unquote_splicing(param_vars(all_params))) do
          SnakeBridge.Runtime.call(
            unquote(library),
            unquote(to_string(function_name)),
            unquote(param_vars(all_params))
          )
        end
      end]
    end)
  end
end
```

### 3.3 Generator Queue

```elixir
# lib/snakebridge/generator.ex
defmodule SnakeBridge.Generator do
  @moduledoc """
  Coordinates lazy generation of Python bindings.
  """

  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def queue(module, function, arity) do
    GenServer.cast(__MODULE__, {:queue, module, function, arity})
  end

  def process_queue do
    GenServer.call(__MODULE__, :process_queue, :infinity)
  end

  # GenServer callbacks

  def init(_) do
    {:ok, %{queue: [], generated: 0}}
  end

  def handle_cast({:queue, module, function, arity}, state) do
    entry = {module, function, arity}
    queue = if entry in state.queue, do: state.queue, else: [entry | state.queue]
    {:noreply, %{state | queue: queue}}
  end

  def handle_call(:process_queue, _from, state) do
    # Group by library for batch introspection
    by_library = Enum.group_by(state.queue, fn {mod, _, _} ->
      {:ok, lib} = SnakeBridge.Registry.get_library(mod)
      lib
    end)

    # Process each library's functions
    generated = Enum.reduce(by_library, 0, fn {library, entries}, count ->
      functions = Enum.map(entries, fn {_, func, _} -> func end)
      {:ok, results} = SnakeBridge.Generator.Introspector.introspect_batch(library, functions)

      Enum.each(results, fn result ->
        module = library.module_name
        {name, arity, asts} = SnakeBridge.Generator.CodeGen.generate_function(module, result)

        # Inject into module
        SnakeBridge.Compiler.Injector.inject(module, asts)

        # Cache
        SnakeBridge.Cache.put(module, name, arity, asts, result)
      end)

      count + length(entries)
    end)

    {:reply, generated, %{state | queue: [], generated: state.generated + generated}}
  end
end
```

## Phase 4: Cache System

**Goal: Persistent cache with accumulation semantics**

### 4.1 Manifest

```elixir
# lib/snakebridge/cache/manifest.ex
defmodule SnakeBridge.Cache.Manifest do
  @moduledoc """
  Manages the cache manifest file.
  """

  @manifest_version "3.0.0"

  defstruct [
    :version,
    :created_at,
    :updated_at,
    entries: %{}
  ]

  def path(cache_dir) do
    Path.join(cache_dir, "cache.manifest")
  end

  def read(cache_dir) do
    case File.read(path(cache_dir)) do
      {:ok, content} ->
        data = Jason.decode!(content)
        {:ok, from_map(data)}
      {:error, :enoent} ->
        {:ok, new()}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def write(manifest, cache_dir) do
    content = Jason.encode!(to_map(manifest), pretty: true)
    File.write(path(cache_dir), content)
  end

  def new do
    %__MODULE__{
      version: @manifest_version,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      entries: %{}
    }
  end

  def add_entry(manifest, key, entry) do
    entries = Map.put(manifest.entries, key, entry)
    %{manifest | entries: entries, updated_at: DateTime.utc_now()}
  end

  def get_entry(manifest, key) do
    Map.get(manifest.entries, key)
  end
end
```

### 4.2 Store

```elixir
# lib/snakebridge/cache/store.ex
defmodule SnakeBridge.Cache.Store do
  @moduledoc """
  Handles cache file storage.
  """

  def init(cache_dir) do
    File.mkdir_p!(cache_dir)
    File.mkdir_p!(Path.join(cache_dir, "libraries"))
    :ok
  end

  def write_beam(cache_dir, module, function, arity, bytecode) do
    dir = library_dir(cache_dir, module)
    File.mkdir_p!(dir)

    path = beam_path(dir, function, arity)
    File.write!(path, bytecode)
    path
  end

  def write_source(cache_dir, module, function, arity, source) do
    dir = library_dir(cache_dir, module)
    File.mkdir_p!(dir)

    path = source_path(dir, function, arity)
    File.write!(path, source)
    path
  end

  def read_beam(cache_dir, module, function, arity) do
    dir = library_dir(cache_dir, module)
    path = beam_path(dir, function, arity)
    File.read(path)
  end

  defp library_dir(cache_dir, module) do
    lib_name = module
    |> Module.split()
    |> hd()
    |> Macro.underscore()

    Path.join([cache_dir, "libraries", lib_name, "functions"])
  end

  defp beam_path(dir, function, arity) do
    Path.join(dir, "#{function}_#{arity}.beam")
  end

  defp source_path(dir, function, arity) do
    Path.join(dir, "#{function}_#{arity}.ex")
  end
end
```

### 4.3 Cache API

```elixir
# lib/snakebridge/cache.ex
defmodule SnakeBridge.Cache do
  @moduledoc """
  Public API for the SnakeBridge cache.
  """

  alias SnakeBridge.Cache.{Manifest, Store, Stats}

  def init(cache_dir \\ "_build/snakebridge") do
    Store.init(cache_dir)
    {:ok, manifest} = Manifest.read(cache_dir)
    :persistent_term.put(:snakebridge_cache_dir, cache_dir)
    :persistent_term.put(:snakebridge_manifest, manifest)
    :ok
  end

  def get(module, function, arity) do
    manifest = :persistent_term.get(:snakebridge_manifest)
    key = cache_key(module, function, arity)

    case Manifest.get_entry(manifest, key) do
      nil ->
        :not_found

      entry ->
        cache_dir = :persistent_term.get(:snakebridge_cache_dir)
        case Store.read_beam(cache_dir, module, function, arity) do
          {:ok, bytecode} ->
            Stats.record_hit(key)
            {:ok, bytecode}
          {:error, _} ->
            :not_found
        end
    end
  end

  def put(module, function, arity, asts, introspection) do
    cache_dir = :persistent_term.get(:snakebridge_cache_dir)
    manifest = :persistent_term.get(:snakebridge_manifest)

    # Compile AST to bytecode
    source = Macro.to_string(asts)
    {:module, _, bytecode, _} = Code.compile_quoted(asts) |> hd()

    # Write files
    beam_path = Store.write_beam(cache_dir, module, function, arity, bytecode)
    source_path = Store.write_source(cache_dir, module, function, arity, source)

    # Update manifest
    key = cache_key(module, function, arity)
    entry = %{
      library: introspection["module"],
      generated_at: DateTime.utc_now(),
      last_used: DateTime.utc_now(),
      use_count: 1,
      beam_file: beam_path,
      source_file: source_path,
      checksum: :crypto.hash(:sha256, bytecode) |> Base.encode16()
    }

    manifest = Manifest.add_entry(manifest, key, entry)
    Manifest.write(manifest, cache_dir)
    :persistent_term.put(:snakebridge_manifest, manifest)

    :ok
  end

  def stats do
    manifest = :persistent_term.get(:snakebridge_manifest)
    Stats.calculate(manifest)
  end

  def list(module) do
    manifest = :persistent_term.get(:snakebridge_manifest)

    manifest.entries
    |> Enum.filter(fn {key, _} -> String.starts_with?(key, "#{module}.") end)
    |> Enum.map(fn {key, entry} ->
      [_, func_arity] = String.split(key, ".", parts: 2)
      [func, arity] = String.split(func_arity, "/")
      {String.to_atom(func), String.to_integer(arity), entry.last_used}
    end)
  end

  defp cache_key(module, function, arity) do
    "#{module}.#{function}/#{arity}"
  end
end
```

## Phase 5: Runtime

**Goal: Execute Python calls at runtime**

### 5.1 Runtime Caller

```elixir
# lib/snakebridge/runtime/caller.ex
defmodule SnakeBridge.Runtime.Caller do
  @moduledoc """
  Executes Python function calls.
  """

  def call(library, function, args) do
    script = call_script(library, function, args)

    case run_python(library, script) do
      {:ok, output} ->
        parse_result(output)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call_script(library, function, args) do
    args_json = Jason.encode!(args)

    """
    import #{library}
    import json

    args = json.loads('#{args_json}')
    func = getattr(#{library}, '#{function}')
    result = func(*args)

    # Convert result to JSON-serializable format
    if hasattr(result, 'tolist'):
        result = result.tolist()
    elif hasattr(result, '__dict__'):
        result = {"__type__": type(result).__name__, "data": str(result)}

    print(json.dumps({"ok": result}))
    """
  end

  defp run_python(library, script) do
    # Use library version from registry
    case SnakeBridge.Registry.get_library_by_name(library) do
      {:ok, lib} when lib.version == :stdlib ->
        System.cmd("python3", ["-c", script], stderr_to_stdout: true)

      {:ok, lib} ->
        version_spec = "#{lib.name}#{lib.version}"
        System.cmd("uv", ["run", "--with", version_spec, "python", "-c", script],
          stderr_to_stdout: true)

      :error ->
        {:error, "Unknown library: #{library}"}
    end
    |> case do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end

  defp parse_result(output) do
    case Jason.decode(output) do
      {:ok, %{"ok" => result}} ->
        {:ok, result}
      {:ok, %{"error" => error}} ->
        {:error, error}
      {:error, _} ->
        {:error, "Failed to parse Python output: #{output}"}
    end
  end
end
```

### 5.2 Public Runtime API

```elixir
# lib/snakebridge/runtime.ex
defmodule SnakeBridge.Runtime do
  @moduledoc """
  Public runtime API for calling Python.
  """

  def call(library, function, args) do
    start_time = System.monotonic_time()

    result = SnakeBridge.Runtime.Caller.call(library, function, args)

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:snakebridge, :call, :stop],
      %{duration: duration},
      %{library: library, function: function, arity: length(args)}
    )

    result
  end
end
```

## Phase 6: Documentation System

**Goal: On-demand documentation fetching**

### 6.1 Doc Fetcher

```elixir
# lib/snakebridge/docs/fetcher.ex
defmodule SnakeBridge.Docs.Fetcher do
  @moduledoc """
  Fetches documentation from Python.
  """

  def fetch(library, function) do
    script = """
    import #{library}
    import inspect
    import json

    obj = getattr(#{library}, '#{function}', None)
    if obj:
        doc = inspect.getdoc(obj) or ""
        try:
            sig = str(inspect.signature(obj))
        except:
            sig = ""
        print(json.dumps({"signature": sig, "docstring": doc}))
    else:
        print(json.dumps({"error": "not_found"}))
    """

    case run_python(library, script) do
      {:ok, output} ->
        case Jason.decode(output) do
          {:ok, %{"error" => _}} -> :not_found
          {:ok, doc} -> {:ok, doc}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

### 6.2 Doc Cache

```elixir
# lib/snakebridge/docs/cache.ex
defmodule SnakeBridge.Docs.Cache do
  @moduledoc """
  Caches documentation in ETS.
  """

  @table :snakebridge_docs

  def init do
    :ets.new(@table, [:set, :public, :named_table])
  end

  def get(module, function) do
    key = {module, function}
    case :ets.lookup(@table, key) do
      [{^key, doc}] -> {:ok, doc}
      [] -> :not_found
    end
  end

  def put(module, function, doc) do
    key = {module, function}
    :ets.insert(@table, {key, doc})
    :ok
  end
end
```

## Phase 7: Mix Tasks

**Goal: Developer-facing CLI tools**

### 7.1 Analyze Task

```elixir
# lib/mix/tasks/snakebridge.analyze.ex
defmodule Mix.Tasks.Snakebridge.Analyze do
  @shortdoc "Analyze SnakeBridge cache"

  use Mix.Task

  def run(_args) do
    SnakeBridge.Cache.init()
    stats = SnakeBridge.Cache.stats()

    Mix.shell().info("""
    SnakeBridge Cache Analysis
    ==========================

    Total entries: #{stats.total_entries}
    Cache size: #{format_size(stats.total_size)}

    By Library:
    #{format_libraries(stats.by_library)}

    Recommendations:
    #{format_recommendations(stats)}
    """)
  end
end
```

### 7.2 Prune Task

```elixir
# lib/mix/tasks/snakebridge.prune.ex
defmodule Mix.Tasks.Snakebridge.Prune do
  @shortdoc "Prune unused cache entries"

  use Mix.Task

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [
      dry_run: :boolean,
      unused_days: :integer,
      force: :boolean
    ])

    SnakeBridge.Cache.init()

    to_prune = SnakeBridge.Cache.find_unused(opts[:unused_days] || 30)

    if opts[:dry_run] do
      Mix.shell().info("Would prune #{length(to_prune)} entries:")
      Enum.each(to_prune, fn entry ->
        Mix.shell().info("  - #{entry.key}")
      end)
    else
      if opts[:force] || confirm_prune(to_prune) do
        SnakeBridge.Cache.prune(to_prune)
        Mix.shell().info("Pruned #{length(to_prune)} entries")
      end
    end
  end
end
```

## Testing Strategy

### Unit Tests

Each module has corresponding unit tests:
- `config_test.exs` - Configuration parsing
- `registry_test.exs` - Library registration
- `introspector_test.exs` - Python introspection (mocked)
- `code_gen_test.exs` - Code generation
- `cache_test.exs` - Cache operations

### Integration Tests

```elixir
# test/integration/numpy_test.exs
defmodule Integration.NumpyTest do
  use ExUnit.Case

  @moduletag :integration

  test "generates and calls numpy.array" do
    {:ok, arr} = Numpy.array([1, 2, 3])
    assert is_list(arr)
    assert arr == [1, 2, 3]
  end
end
```

### CI Pipeline

```yaml
# .github/workflows/test.yml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: "1.16"
          otp-version: "26"
      - uses: astral-sh/setup-uv@v4

      - run: mix deps.get
      - run: mix test
      - run: mix test --include integration
```

## Milestones

| Phase | Milestone | Deliverable |
|-------|-----------|-------------|
| 0 | Foundation | Clean project structure |
| 1 | Configuration | Library parsing from mix.exs |
| 2 | Compiler | Tracer detects library calls |
| 3 | Generation | First bindings generated |
| 4 | Cache | Bindings persist across compiles |
| 5 | Runtime | Python calls work |
| 6 | Documentation | On-demand docs |
| 7 | CLI | Developer tools |
| - | **v3.0.0** | **Full release** |
