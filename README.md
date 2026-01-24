<p align="center">
  <img src="assets/snakebridge.svg" alt="SnakeBridge Logo">
</p>

# SnakeBridge

[![Hex.pm](https://img.shields.io/hexpm/v/snakebridge.svg)](https://hex.pm/packages/snakebridge)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/snakebridge)

Type-safe Elixir bindings to Python libraries with compile-time code generation and runtime FFI.

## Installation

```elixir
# mix.exs
def project do
  [
    app: :my_app,
    deps: deps(),
    python_deps: python_deps(),
    compilers: [:snakebridge] ++ Mix.compilers()
  ]
end

defp deps do
  [{:snakebridge, "~> 0.14.0"}]
end

defp python_deps do
  [
    {:numpy, "1.26.0"},
    {:pandas, "2.0.0", include: ["DataFrame", "read_csv"]},
    {:json, :stdlib}
  ]
end
```

Add runtime configuration in `config/runtime.exs`:

```elixir
import Config
SnakeBridge.ConfigHelper.configure_snakepit!()
```

Then fetch and compile:

```bash
mix deps.get && mix compile
mix snakebridge.setup  # Creates managed venv + installs Python packages
```

SnakeBridge uses the managed venv at `priv/snakepit/python/venv` by default; no manual venv setup required.

## Quick Start

### Universal FFI (Any Python Module)

Call any Python function dynamically without code generation:

```elixir
# Simple function calls
{:ok, 4.0} = SnakeBridge.call("math", "sqrt", [16])
{:ok, pi} = SnakeBridge.get("math", "pi")

# Create Python objects (refs)
{:ok, path} = SnakeBridge.call("pathlib", "Path", ["/tmp/file.txt"])
{:ok, exists?} = SnakeBridge.method(path, "exists", [])
{:ok, name} = SnakeBridge.attr(path, "name")

# Binary data with explicit bytes encoding
{:ok, md5} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("data")])
{:ok, hex} = SnakeBridge.method(md5, "hexdigest", [])

# Bang variants raise on error
result = SnakeBridge.call!("json", "dumps", [%{key: "value"}])
```

### Generated Wrappers (Configured Libraries)

Libraries in `python_deps` get Elixir modules with type hints and docs:

```elixir
# Call like native Elixir
{:ok, result} = Numpy.mean([1, 2, 3, 4])
{:ok, result} = Numpy.mean([[1, 2], [3, 4]], axis: 0)

# Classes generate new/N constructors
{:ok, df} = Pandas.DataFrame.new(%{"a" => [1, 2], "b" => [3, 4]})

# Discovery APIs
Numpy.__functions__()        # List all functions
Numpy.__search__("mean")     # Search by name
```

### When to Use Which

| Scenario | Use |
|----------|-----|
| Core library (NumPy, Pandas) | Generated wrappers |
| One-off stdlib call | Universal FFI |
| Runtime-determined module | Universal FFI |
| IDE autocomplete needed | Generated wrappers |

Both approaches coexist in the same project.

## Core Concepts

### Python Object References

Non-serializable Python objects return as refs - handles to objects in Python memory:

```elixir
{:ok, ref} = SnakeBridge.call("collections", "Counter", [["a", "b", "a"]])
SnakeBridge.ref?(ref)  # true

# Call methods and access attributes
{:ok, count} = SnakeBridge.method(ref, "most_common", [2])
```

### Session Management

Refs are scoped to sessions. By default, each Elixir process gets an auto-session:

```elixir
# Explicit session scope
SnakeBridge.SessionContext.with_session(session_id: "my-session", fn ->
  {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
  # ref.session_id == "my-session"
end)

# Release session explicitly
SnakeBridge.release_auto_session()
```

### Graceful Serialization

Containers preserve structure - only non-serializable leaves become refs:

```elixir
{:ok, result} = SnakeBridge.call("module", "get_mixed_data", [])
# result = %{"name" => "test", "handler" => %SnakeBridge.Ref{...}}
# String fields accessible directly, handler is a ref
```

### Type Encoding

| Elixir | Python | Notes |
|--------|--------|-------|
| `integer` | `int` | Direct |
| `float` | `float` | Direct |
| `binary` | `str` | UTF-8 strings |
| `list` | `list` | Recursive |
| `map` | `dict` | String keys direct |
| `nil` | `None` | Direct |
| `SnakeBridge.bytes(data)` | `bytes` | Explicit binary |

See [Type System Guide](guides/TYPE_SYSTEM.md) for complete mapping.

## Configuration

### python_deps Options

```elixir
defp python_deps do
  [
    {:numpy, "1.26.0",
      pypi_package: "numpy",          # PyPI name if different
      extras: ["sql"],                # pip extras
      include: ["array", "mean"],     # Only these symbols
      exclude: ["testing"],           # Exclude these
      submodules: true,               # Include submodules
      public_api: true,               # Filter to public API modules only
      generate: :all,                 # Generate all symbols
      streaming: ["generate"],        # *_stream variants
      min_signature_tier: :stub},     # Signature quality threshold

    {:math, :stdlib}                  # Standard library module
  ]
end
```

### Application Config

```elixir
# config/config.exs
config :snakebridge,
  generated_dir: "lib/snakebridge_generated",
  generated_layout: :split,  # :split (default) | :single
  metadata_dir: ".snakebridge",
  strict: false,
  error_mode: :raw,  # :raw | :translated | :raise_translated
  atom_allowlist: ["ok", "error"]
```

Generated files mirror Python module structure (`dspy/predict/__init__.ex` for `Dspy.Predict`).
See [Generated Wrappers](guides/GENERATED_WRAPPERS.md) for details.

### Runtime Options

Pass via `__runtime__:` key:

```elixir
SnakeBridge.call("module", "fn", [args],
  __runtime__: [
    session_id: "custom",
    timeout: 60_000,
    affinity: :strict_queue,
    pool_name: :gpu_pool
  ]
)
```

### Runtime Defaults (Process-Scoped)

Set defaults once per process:

```elixir
SnakeBridge.RuntimeContext.put_defaults(
  pool_name: :gpu_pool,
  timeout_profile: :ml_inference
)
```

Or scope them to a block:

```elixir
SnakeBridge.with_runtime(pool_name: :gpu_pool, timeout_profile: :ml_inference) do
  {:ok, result} = SnakeBridge.call("module", "fn", [args])
  result
end
```

Helper shortcuts for common option shapes:

```elixir
SnakeBridge.call("numpy", "mean", [scores], SnakeBridge.rt(pool_name: :gpu_pool))

SnakeBridge.call("numpy", "mean", [scores],
  SnakeBridge.opts(py: [axis: 0], runtime: [pool_name: :gpu_pool])
)
```

### Testing

Use the built-in ExUnit template for automatic setup/teardown:

```elixir
defmodule MyApp.SomeFeatureTest do
  use SnakeBridge.TestCase, pool: :dspy_pool

  test "runs pipeline" do
    {:ok, out} = Dspy.SomeModule.some_call("x", y: 1)
    assert out != nil
  end
end
```

## Advanced Features

### Streaming and Generators

```elixir
# Generators implement Enumerable
{:ok, counter} = SnakeBridge.call("itertools", "count", [1])
Enum.take(counter, 5)  # [1, 2, 3, 4, 5]

# Callback-based streaming
SnakeBridge.stream("llm", "generate", ["prompt"], [], fn chunk ->
  IO.write(chunk)
end)
```

### ML Error Translation

```elixir
config :snakebridge, error_mode: :translated

# Python errors become structured Elixir errors
%SnakeBridge.Error.ShapeMismatchError{expected: [3, 4], actual: [4, 3]}
%SnakeBridge.Error.OutOfMemoryError{device: :cuda, requested: 2048}
```

### Protocol Integration

Refs implement Elixir protocols:

```elixir
{:ok, ref} = SnakeBridge.call("builtins", "range", [0, 5])
inspect(ref)        # Uses __repr__
"Range: #{ref}"     # Uses __str__
Enum.count(ref)     # Uses __len__
Enum.to_list(ref)   # Uses __iter__
```

### Session Affinity

For stateful workloads, ensure refs route to the same worker:

```elixir
SnakeBridge.ConfigHelper.configure_snakepit!(affinity: :strict_queue)

# Or per-call
SnakeBridge.method(ref, "compute", [], __runtime__: [affinity: :strict_fail_fast])
```

Modes: `:hint` (default), `:strict_queue`, `:strict_fail_fast`

### Telemetry

```elixir
:telemetry.attach("my-handler", [:snakebridge, :compile, :stop], fn _, m, _, _ ->
  IO.puts("Generated #{m.symbols_generated} symbols")
end, nil)
```

Events: `[:snakebridge, :compile, :*]`, `[:snakebridge, :runtime, :call, :*]`, `[:snakebridge, :session, :cleanup]`

## Mix Tasks

```bash
mix snakebridge.setup          # Install Python packages
mix snakebridge.setup --check  # Verify installation
mix snakebridge.verify         # Hardware compatibility check
```

## Script Execution

For scripts and Mix tasks:

```elixir
SnakeBridge.script do
  {:ok, result} = SnakeBridge.call("math", "sqrt", [16])
  IO.inspect(result)
end
```

`SnakeBridge.run_as_script/2` remains available for custom lifecycle options.

## Before/After

**Test setup**

Before:

```elixir
setup_all do
  Application.ensure_all_started(:snakebridge)
  SnakeBridge.ConfigHelper.configure_snakepit!()
  :ok
end

setup do
  SnakeBridge.Runtime.clear_auto_session()
  on_exit(fn -> SnakeBridge.release_auto_session() end)
end
```

After:

```elixir
defmodule MyApp.SomeFeatureTest do
  use SnakeBridge.TestCase, pool: :demo_pool
end
```

**Pool selection defaults**

Before:

```elixir
SnakeBridge.call("numpy", "mean", [scores],
  __runtime__: [pool_name: :analytics_pool, timeout_profile: :ml_inference]
)
```

After:

```elixir
SnakeBridge.with_runtime(pool_name: :analytics_pool, timeout_profile: :ml_inference) do
  SnakeBridge.call("numpy", "mean", [scores])
end
```

**Callbacks**

Before:

```elixir
SnakeBridge.SessionContext.with_session([session_id: "shared"], fn ->
  SnakeBridge.call("module", "fn", [fn x -> x end])
end)
```

After:

```elixir
SnakeBridge.call("module", "fn", [fn x -> x end])
```

## Guides

| Guide | Description |
|-------|-------------|
| [Getting Started](guides/GETTING_STARTED.md) | Installation, setup, first calls |
| [Universal FFI](guides/UNIVERSAL_FFI.md) | Dynamic Python calls without codegen |
| [Generated Wrappers](guides/GENERATED_WRAPPERS.md) | Compile-time code generation |
| [Type System](guides/TYPE_SYSTEM.md) | Wire protocol and type encoding |
| [Refs and Sessions](guides/REFS_AND_SESSIONS.md) | Python object lifecycle |
| [Session Affinity](guides/SESSION_AFFINITY.md) | Worker routing for stateful workloads |
| [Streaming](guides/STREAMING.md) | Generators, iterators, streaming calls |
| [Error Handling](guides/ERROR_HANDLING.md) | Exception translation |
| [Telemetry](guides/TELEMETRY.md) | Observability and metrics |
| [Best Practices](guides/BEST_PRACTICES.md) | Patterns and recommendations |
| [Coverage Reports](guides/COVERAGE_REPORTS.md) | Signature and doc coverage |
| [Configuration Reference](guides/CONFIGURATION.md) | All configuration options |

## Examples

The `examples/` directory contains runnable demonstrations:

```bash
./examples/run_all.sh                    # Run all
cd examples/basic && mix run -e Demo.run # Individual
```

Key examples:
- `universal_ffi_example` - Complete Universal FFI showcase
- `multi_session_example` - Concurrent isolated sessions
- `streaming_example` - Callback-based streaming
- `error_showcase` - ML error translation
- `signature_showcase` - Signature model and arities

See [Examples Overview](examples/README.md) for the complete list.

## Architecture

SnakeBridge operates in two phases:

**Compile-time**: Scans your code, introspects Python modules, generates typed Elixir wrappers with proper arities and documentation.

**Runtime**: Delegates calls to [Snakepit](https://hex.pm/packages/snakepit), which manages a gRPC-connected Python process pool.

### Wire Protocol

Uses JSON-over-gRPC with tagged types (`__type__`, `__schema__`) for non-JSON values. Protocol version 1 with strict compatibility checking.

### Timeout Profiles

| Profile | Timeout | Stream Timeout |
|---------|---------|----------------|
| `:default` | 2 min | - |
| `:streaming` | 2 min | 30 min |
| `:ml_inference` | 10 min | 30 min |
| `:batch_job` | infinity | infinity |

```elixir
SnakeBridge.call("module", "fn", [], __runtime__: [timeout_profile: :ml_inference])
```

## Requirements

- Elixir ~> 1.14
- Python 3.8+
- [uv](https://docs.astral.sh/uv/) - Fast Python package manager

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh  # Install uv
```

## License

MIT
