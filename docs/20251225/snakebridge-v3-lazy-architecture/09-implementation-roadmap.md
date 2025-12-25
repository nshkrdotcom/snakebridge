# Implementation Roadmap

## Overview

This document outlines the technical implementation plan for SnakeBridge v3. The architecture uses a **pre-compilation generation pass** that produces real `.ex` source files, avoiding the fragility of mid-compilation injection.

## Architecture Summary

```
mix compile
    │
    ├── 1. SnakeBridge Compiler (runs first)
    │       ├── Scan project AST
    │       ├── Compare to manifest
    │       ├── Generate missing .ex files
    │       └── Update manifest + lock
    │
    ├── 2. Elixir Compiler (normal)
    │       └── Compiles all .ex including generated
    │
    └── 3. App Compiler (normal)
            └── Standard application compilation
```

## Phase 0: Foundation

**Goal: Clean project structure for v3**

### 0.1 Project Layout

```
lib/
├── snakebridge.ex                    # Public API
├── snakebridge/
│   ├── config.ex                     # Configuration from mix.exs
│   ├── scanner.ex                    # AST scanning
│   ├── introspector.ex               # Python introspection
│   ├── generator.ex                  # Source generation
│   ├── manifest.ex                   # Manifest management
│   ├── lock.ex                       # Lock file management
│   ├── ledger.ex                     # Runtime usage ledger
│   └── runtime.ex                    # Python call interface
├── mix/
│   └── tasks/
│       ├── compile/
│       │   └── snakebridge.ex        # Compiler task
│       ├── snakebridge.generate.ex
│       ├── snakebridge.prune.ex
│       ├── snakebridge.verify.ex
│       ├── snakebridge.ledger.ex
│       └── snakebridge.promote.ex
test/
├── snakebridge/
│   ├── config_test.exs
│   ├── scanner_test.exs
│   ├── generator_test.exs
│   └── manifest_test.exs
└── integration/
    ├── numpy_test.exs
    └── stdlib_test.exs
```

### 0.2 Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:jason, "~> 1.4"},           # JSON parsing
    {:telemetry, "~> 1.0"},       # Metrics
  ]
end
```

No Python dependencies in Elixir—UV handles all Python package management.

---

## Phase 1: Configuration

**Goal: Parse library configuration from mix.exs**

### 1.1 Configuration Parser

```elixir
defmodule SnakeBridge.Config do
  @moduledoc """
  Parses SnakeBridge configuration from mix.exs dependency options.
  """

  defstruct [
    :libraries,
    :generated_dir,
    :metadata_dir,
    :verbose
  ]

  @type library :: %{
    name: atom(),
    python_name: String.t(),
    version: String.t() | :stdlib,
    module_name: module()
  }

  def load do
    deps = Mix.Project.config()[:deps] || []

    case find_snakebridge_dep(deps) do
      {_, opts} when is_list(opts) ->
        parse(opts)
      _ ->
        %__MODULE__{libraries: []}
    end
  end

  defp find_snakebridge_dep(deps) do
    Enum.find(deps, fn
      {:snakebridge, _} -> true
      {:snakebridge, _, _} -> true
      _ -> false
    end)
  end

  def parse(opts) do
    libraries = parse_libraries(opts[:libraries] || [])

    %__MODULE__{
      libraries: libraries,
      generated_dir: opts[:generated_dir] || "lib/snakebridge_generated",
      metadata_dir: opts[:metadata_dir] || ".snakebridge",
      verbose: opts[:verbose] || false
    }
  end

  defp parse_libraries(libs) do
    Enum.map(libs, &parse_library/1)
  end

  defp parse_library({name, :stdlib}) do
    %{
      name: name,
      python_name: to_string(name),
      version: :stdlib,
      module_name: module_name(name)
    }
  end

  defp parse_library({name, version}) when is_binary(version) do
    %{
      name: name,
      python_name: to_string(name),
      version: version,
      module_name: module_name(name)
    }
  end

  defp parse_library({name, opts}) when is_list(opts) do
    %{
      name: name,
      python_name: opts[:python_name] || to_string(name),
      version: opts[:version],
      module_name: opts[:module_name] || module_name(name)
    }
  end

  defp module_name(name) do
    name
    |> to_string()
    |> Macro.camelize()
    |> String.to_atom()
  end

  def library_modules do
    load().libraries |> Enum.map(& &1.module_name)
  end

  def get_library(module) do
    load().libraries |> Enum.find(& &1.module_name == module)
  end
end
```

### 1.2 Tests

```elixir
defmodule SnakeBridge.ConfigTest do
  use ExUnit.Case

  test "parses simple version string" do
    config = SnakeBridge.Config.parse(libraries: [numpy: "~> 1.26"])

    assert [lib] = config.libraries
    assert lib.name == :numpy
    assert lib.version == "~> 1.26"
    assert lib.module_name == Numpy
  end

  test "parses stdlib" do
    config = SnakeBridge.Config.parse(libraries: [json: :stdlib])

    assert [lib] = config.libraries
    assert lib.version == :stdlib
  end

  test "parses custom module name" do
    config = SnakeBridge.Config.parse(libraries: [
      numpy: [version: "~> 1.26", module_name: Np]
    ])

    assert [lib] = config.libraries
    assert lib.module_name == Np
  end
end
```

---

## Phase 2: AST Scanner

**Goal: Detect library calls in project source**

### 2.1 Scanner Implementation

```elixir
defmodule SnakeBridge.Scanner do
  @moduledoc """
  Scans project source files for Python library function calls.
  """

  def scan_project do
    config = SnakeBridge.Config.load()
    library_modules = Enum.map(config.libraries, & &1.module_name)

    source_files(config)
    |> Task.async_stream(&scan_file(&1, library_modules), ordered: false)
    |> Enum.flat_map(fn {:ok, calls} -> calls end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp source_files(config) do
    elixirc_paths = Mix.Project.config()[:elixirc_paths] || ["lib"]

    elixirc_paths
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))
    |> Enum.reject(&String.starts_with?(&1, config.generated_dir))
  end

  defp scan_file(path, library_modules) do
    content = File.read!(path)

    case Code.string_to_quoted(content, file: path) do
      {:ok, ast} ->
        extract_calls(ast, library_modules)
      {:error, _} ->
        []  # Skip files with syntax errors
    end
  end

  defp extract_calls(ast, library_modules) do
    {_, calls} = Macro.prewalk(ast, [], fn
      # Remote call: Numpy.array(x)
      {{:., _, [{:__aliases__, _, module_parts}, function]}, _, args}, acc
      when is_atom(function) and is_list(args) ->
        module = Module.concat(module_parts)
        if module in library_modules do
          call = {module, function, length(args)}
          {nil, [call | acc]}
        else
          {nil, acc}
        end

      node, acc ->
        {node, acc}
    end)

    calls
  end
end
```

---

## Phase 3: Introspection

**Goal: Query Python for function signatures and docs**

### 3.1 Introspector Implementation

```elixir
defmodule SnakeBridge.Introspector do
  @moduledoc """
  Introspects Python functions using UV.
  """

  def introspect(library, functions) when is_list(functions) do
    script = introspection_script(library.python_name, functions)

    case run_python(library, script) do
      {:ok, output} ->
        parse_output(output)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp introspection_script(python_name, functions) do
    functions_json = Jason.encode!(Enum.map(functions, &to_string/1))

    """
    import #{python_name}
    import inspect
    import json
    import sys

    functions = json.loads('#{String.replace(functions_json, "'", "\\'")}')
    results = []

    for func_name in functions:
        try:
            obj = getattr(#{python_name}, func_name, None)
            if obj is None:
                results.append({"name": func_name, "error": "not_found"})
                continue

            # Get signature
            try:
                sig = inspect.signature(obj)
                params = []
                for p in sig.parameters.values():
                    param = {
                        "name": p.name,
                        "kind": str(p.kind).split('.')[-1],
                    }
                    if p.default != inspect.Parameter.empty:
                        param["default"] = repr(p.default)
                    if p.annotation != inspect.Parameter.empty:
                        param["annotation"] = str(p.annotation)
                    params.append(param)
            except (ValueError, TypeError):
                params = []

            # Get docstring
            doc = inspect.getdoc(obj) or ""

            results.append({
                "name": func_name,
                "parameters": params,
                "docstring": doc[:4000],
                "callable": callable(obj)
            })
        except Exception as e:
            results.append({"name": func_name, "error": str(e)})

    print(json.dumps(results))
    """
  end

  defp run_python(library, script) do
    {cmd, args} = if library.version == :stdlib do
      {"python3", ["-c", script]}
    else
      version_spec = "#{library.python_name}#{library.version}"
      {"uv", ["run", "--with", version_spec, "python", "-c", script]}
    end

    case System.cmd(cmd, args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {error, code} -> {:error, {code, error}}
    end
  end

  defp parse_output(output) do
    case Jason.decode(output) do
      {:ok, results} -> {:ok, results}
      {:error, _} -> {:error, {:json_parse, output}}
    end
  end
end
```

---

## Phase 4: Generator

**Goal: Produce deterministic `.ex` source files**

### 4.1 Generator Implementation

```elixir
defmodule SnakeBridge.Generator do
  @moduledoc """
  Generates Elixir source files from introspection data.
  """

  def generate(to_generate, config) do
    File.mkdir_p!(config.generated_dir)

    # Group by library
    by_library = Enum.group_by(to_generate, fn {mod, _, _} ->
      SnakeBridge.Config.get_library(mod)
    end)

    Enum.each(by_library, fn {library, calls} ->
      generate_library(library, calls, config)
    end)
  end

  defp generate_library(library, calls, config) do
    # Get function names
    functions = calls
    |> Enum.map(fn {_mod, func, _arity} -> func end)
    |> Enum.uniq()

    # Introspect Python
    {:ok, introspection} = SnakeBridge.Introspector.introspect(library, functions)

    # Load existing functions from generated file
    path = Path.join(config.generated_dir, "#{library.name}.ex")
    existing = parse_existing_functions(path)

    # Merge and generate
    all_functions = merge_functions(existing, introspection)
    source = generate_module(library, all_functions)

    # Write atomically
    write_atomic(path, source)

    if config.verbose do
      Mix.shell().info("SnakeBridge: Generated #{path}")
    end
  end

  defp parse_existing_functions(path) do
    case File.read(path) do
      {:ok, content} ->
        # Extract function info from existing generated file
        # This preserves functions that were previously generated
        extract_functions_from_source(content)
      {:error, :enoent} ->
        []
    end
  end

  defp merge_functions(existing, new_introspection) do
    new_by_name = Map.new(new_introspection, fn info -> {info["name"], info} end)
    existing_by_name = Map.new(existing, fn info -> {info["name"], info} end)

    Map.merge(existing_by_name, new_by_name)
    |> Map.values()
    |> Enum.reject(&Map.has_key?(&1, "error"))
    |> Enum.sort_by(& &1["name"])
  end

  defp generate_module(library, functions) do
    function_defs = Enum.map(functions, &generate_function/1)
    |> Enum.join("\n\n")

    """
    # Generated by SnakeBridge - DO NOT EDIT MANUALLY
    # Regenerate with: mix snakebridge.generate
    #
    # Library: #{library.python_name} #{library.version}
    # Generated: #{DateTime.utc_now() |> DateTime.to_iso8601()}

    defmodule #{library.module_name} do
      @moduledoc \"\"\"
      SnakeBridge bindings for `#{library.python_name}`.

      These functions call Python through the SnakeBridge runtime.
      For documentation, use `#{library.module_name}.doc(:function_name)`.
      \"\"\"

    #{function_defs}

      @doc false
      def doc(function) do
        SnakeBridge.Docs.get(__MODULE__, function)
      end

      @doc false
      def search(query) do
        SnakeBridge.Docs.search(__MODULE__, query)
      end
    end
    """
  end

  defp generate_function(info) do
    name = info["name"]
    params = info["parameters"] || []
    doc = info["docstring"] || ""

    param_names = Enum.map(params, fn p -> p["name"] end)
    param_list = Enum.join(param_names, ", ")

    doc_escaped = escape_heredoc(doc)

    """
      @doc \"\"\"
    #{indent(doc_escaped, 2)}
      \"\"\"
      def #{name}(#{param_list}) do
        SnakeBridge.Runtime.call(__MODULE__, :#{name}, [#{param_list}])
      end
    """
  end

  defp escape_heredoc(text) do
    text
    |> String.replace("\"\"\"", "\\\"\\\"\\\"")
    |> String.trim()
  end

  defp indent(text, spaces) do
    prefix = String.duplicate(" ", spaces)
    text
    |> String.split("\n")
    |> Enum.map(&(prefix <> &1))
    |> Enum.join("\n")
  end

  defp write_atomic(path, content) do
    temp = path <> ".tmp.#{:rand.uniform(100_000)}"
    File.write!(temp, content)
    File.rename!(temp, path)
  end
end
```

---

## Phase 5: Compiler Task

**Goal: Integrate with Mix compilation**

### 5.1 Compiler Task

```elixir
defmodule Mix.Tasks.Compile.Snakebridge do
  @moduledoc """
  SnakeBridge compiler task.

  Runs before the Elixir compiler to scan for library usage
  and generate bindings as needed.
  """
  use Mix.Task.Compiler

  @impl true
  def run(_args) do
    config = SnakeBridge.Config.load()

    if config.libraries == [] do
      {:ok, []}
    else
      do_compile(config)
    end
  end

  defp do_compile(config) do
    # 1. Scan project for library calls
    detected = SnakeBridge.Scanner.scan_project()

    if config.verbose do
      Mix.shell().info("SnakeBridge: Detected #{length(detected)} library calls")
    end

    # 2. Load manifest
    manifest = SnakeBridge.Manifest.load(config)

    # 3. Find what needs generation
    to_generate = SnakeBridge.Manifest.missing(manifest, detected)

    # 4. Generate if needed
    if to_generate != [] do
      if config.verbose do
        Mix.shell().info("SnakeBridge: Generating #{length(to_generate)} new bindings")
      end

      SnakeBridge.Generator.generate(to_generate, config)
    end

    # 5. Update manifest
    SnakeBridge.Manifest.update(manifest, detected, config)

    # 6. Update lock file
    SnakeBridge.Lock.update(config)

    {:ok, []}
  end

  @impl true
  def manifests do
    config = SnakeBridge.Config.load()
    [SnakeBridge.Manifest.path(config)]
  end

  @impl true
  def clean do
    config = SnakeBridge.Config.load()

    # Remove generated files
    if File.exists?(config.generated_dir) do
      File.rm_rf!(config.generated_dir)
    end

    # Remove metadata
    if File.exists?(config.metadata_dir) do
      File.rm_rf!(config.metadata_dir)
    end

    :ok
  end
end
```

---

## Phase 6: Manifest and Lock

**Goal: Track generated symbols and environment**

### 6.1 Manifest

```elixir
defmodule SnakeBridge.Manifest do
  @moduledoc """
  Manages the symbol manifest - what has been generated.
  """

  def path(config) do
    Path.join(config.metadata_dir, "manifest.json")
  end

  def load(config) do
    path = path(config)

    case File.read(path) do
      {:ok, content} ->
        Jason.decode!(content)
      {:error, :enoent} ->
        %{"version" => "3.0.0", "symbols" => %{}}
    end
  end

  def missing(manifest, detected) do
    existing = manifest["symbols"] |> Map.keys() |> MapSet.new()

    detected
    |> Enum.map(fn {mod, func, arity} -> "#{mod}.#{func}/#{arity}" end)
    |> MapSet.new()
    |> MapSet.difference(existing)
    |> MapSet.to_list()
    |> Enum.map(&parse_symbol_key/1)
  end

  defp parse_symbol_key(key) do
    [mod_func, arity] = String.split(key, "/")
    [mod, func] = String.split(mod_func, ".", parts: 2)

    {String.to_atom("Elixir." <> mod), String.to_atom(func), String.to_integer(arity)}
  end

  def update(manifest, detected, config) do
    symbols = Enum.reduce(detected, manifest["symbols"], fn {mod, func, arity}, acc ->
      key = "#{mod}.#{func}/#{arity}"
      Map.put_new(acc, key, %{
        "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      })
    end)

    new_manifest = %{
      "version" => "3.0.0",
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "symbols" => symbols |> Enum.sort() |> Map.new()
    }

    path = path(config)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(new_manifest, pretty: true))
  end
end
```

### 6.2 Lock

```elixir
defmodule SnakeBridge.Lock do
  @moduledoc """
  Manages the lock file - environment identity for reproducibility.
  """

  @lock_file "snakebridge.lock"

  def path, do: @lock_file

  def load do
    case File.read(@lock_file) do
      {:ok, content} -> Jason.decode!(content)
      {:error, :enoent} -> nil
    end
  end

  def update(config) do
    environment = %{
      "snakebridge_version" => Application.spec(:snakebridge, :vsn) |> to_string(),
      "python_version" => get_python_version(),
      "python_platform" => get_python_platform(),
      "elixir_version" => System.version(),
      "otp_version" => :erlang.system_info(:otp_release) |> to_string()
    }

    libraries = Enum.map(config.libraries, fn lib ->
      {to_string(lib.name), %{
        "requested" => to_string(lib.version),
        "resolved" => resolve_version(lib)
      }}
    end) |> Map.new()

    lock = %{
      "version" => "3.0.0",
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "environment" => environment,
      "libraries" => libraries
    }

    File.write!(@lock_file, Jason.encode!(lock, pretty: true))
  end

  defp get_python_version do
    case System.cmd("python3", ["--version"]) do
      {output, 0} -> output |> String.trim() |> String.replace("Python ", "")
      _ -> "unknown"
    end
  end

  defp get_python_platform do
    case System.cmd("python3", ["-c", "import platform; print(platform.platform())"]) do
      {output, 0} -> String.trim(output)
      _ -> "unknown"
    end
  end

  defp resolve_version(lib) when lib.version == :stdlib, do: "stdlib"
  defp resolve_version(_lib), do: "resolved"  # TODO: Get actual resolved version
end
```

---

## Phase 7: Runtime

**Goal: Execute Python calls**

### 7.1 Runtime

```elixir
defmodule SnakeBridge.Runtime do
  @moduledoc """
  Executes Python function calls at runtime.
  """

  def call(module, function, args) do
    library = SnakeBridge.Config.get_library(module)

    # Record to ledger in dev
    if Mix.env() == :dev do
      SnakeBridge.Ledger.record(module, function, length(args))
    end

    # Execute call
    execute(library, function, args)
  end

  defp execute(library, function, args) do
    script = call_script(library.python_name, function, args)

    case run_python(library, script) do
      {:ok, output} -> parse_result(output)
      {:error, reason} -> {:error, reason}
    end
  end

  defp call_script(python_name, function, args) do
    args_json = Jason.encode!(args)

    """
    import #{python_name}
    import json

    args = json.loads('#{String.replace(args_json, "'", "\\'")}')
    func = getattr(#{python_name}, '#{function}')
    result = func(*args)

    # Convert to JSON-serializable
    def jsonify(obj):
        if hasattr(obj, 'tolist'):
            return obj.tolist()
        elif hasattr(obj, '__dict__'):
            return {"__class__": type(obj).__name__, "value": str(obj)}
        else:
            return obj

    print(json.dumps({"ok": jsonify(result)}))
    """
  end

  defp run_python(library, script) do
    {cmd, args} = if library.version == :stdlib do
      {"python3", ["-c", script]}
    else
      {"uv", ["run", "--with", "#{library.python_name}#{library.version}", "python", "-c", script]}
    end

    case System.cmd(cmd, args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {error, _} -> {:error, error}
    end
  end

  defp parse_result(output) do
    case Jason.decode(output) do
      {:ok, %{"ok" => result}} -> {:ok, result}
      {:ok, %{"error" => error}} -> {:error, error}
      {:error, _} -> {:error, {:parse_error, output}}
    end
  end
end
```

---

## Phase 8: Mix Tasks

**Goal: Developer-facing CLI tools**

### 8.1 Generate Task

```elixir
defmodule Mix.Tasks.Snakebridge.Generate do
  @shortdoc "Generate Python library bindings"
  @moduledoc """
  Generates bindings for detected Python library usage.

  ## Usage

      mix snakebridge.generate         # Generate for detected usage
      mix snakebridge.generate numpy   # Generate for specific library
      mix snakebridge.generate --force # Force regeneration
  """
  use Mix.Task

  def run(args) do
    {opts, libs, _} = OptionParser.parse(args, switches: [force: :boolean])

    config = SnakeBridge.Config.load()

    if opts[:force] do
      # Clear and regenerate
      File.rm_rf!(config.generated_dir)
      File.rm_rf!(config.metadata_dir)
    end

    # Trigger compilation which will generate
    Mix.Task.run("compile", ["--force"])
  end
end
```

### 8.2 Prune Task

```elixir
defmodule Mix.Tasks.Snakebridge.Prune do
  @shortdoc "Remove unused generated bindings"
  @moduledoc """
  Prunes bindings that are no longer used in the project.

  ## Usage

      mix snakebridge.prune            # Preview what would be pruned
      mix snakebridge.prune --force    # Actually prune
  """
  use Mix.Task

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [force: :boolean])

    config = SnakeBridge.Config.load()
    detected = SnakeBridge.Scanner.scan_project()
    manifest = SnakeBridge.Manifest.load(config)

    detected_keys = MapSet.new(detected, fn {mod, func, arity} ->
      "#{mod}.#{func}/#{arity}"
    end)

    existing_keys = manifest["symbols"] |> Map.keys() |> MapSet.new()
    unused = MapSet.difference(existing_keys, detected_keys) |> MapSet.to_list()

    if unused == [] do
      Mix.shell().info("No unused bindings to prune.")
    else
      Mix.shell().info("Unused bindings (#{length(unused)}):")
      Enum.each(unused, &Mix.shell().info("  - #{&1}"))

      if opts[:force] do
        prune_symbols(unused, config)
        Mix.shell().info("Pruned #{length(unused)} bindings.")
      else
        Mix.shell().info("\nRun with --force to prune.")
      end
    end
  end
end
```

---

## Testing Strategy

### Unit Tests

```elixir
# test/snakebridge/scanner_test.exs
defmodule SnakeBridge.ScannerTest do
  use ExUnit.Case

  test "detects library calls in source" do
    # Create temp file with library call
    source = """
    defmodule Test do
      def foo do
        Numpy.array([1, 2, 3])
      end
    end
    """

    # Test scanning
  end
end
```

### Integration Tests

```elixir
# test/integration/numpy_test.exs
defmodule Integration.NumpyTest do
  use ExUnit.Case

  @moduletag :integration

  test "generates and calls numpy.array" do
    {:ok, arr} = Numpy.array([1, 2, 3])
    assert arr == [1, 2, 3]
  end
end
```

---

## Milestones

| Phase | Deliverable | Success Criteria |
|-------|-------------|------------------|
| 0 | Project structure | Clean layout, deps in place |
| 1 | Configuration | Parses mix.exs libraries correctly |
| 2 | Scanner | Detects all library calls in project |
| 3 | Introspector | Gets Python function signatures |
| 4 | Generator | Produces valid, sorted `.ex` files |
| 5 | Compiler | Integrates with `mix compile` |
| 6 | Manifest/Lock | Tracks symbols, environment |
| 7 | Runtime | Executes Python calls |
| 8 | Mix Tasks | generate, prune, verify work |
| **v3.0.0** | **Full Release** | All tests pass, docs complete |

---

## MVP Definition

**Minimum for v3.0.0 release:**

1. Configuration parsing from mix.exs
2. AST scanning for library calls
3. Python introspection via UV
4. Source generation to `lib/snakebridge_generated/`
5. Manifest tracking of generated symbols
6. Lock file for environment identity
7. Runtime Python execution
8. `mix compile` integration
9. `mix snakebridge.generate` task
10. `mix snakebridge.prune` task

**Deferred to v3.1+:**

- Shared cache server
- Community registry packages
- Advanced type mapping
- GPU/CUDA support
- Pooled Python processes
