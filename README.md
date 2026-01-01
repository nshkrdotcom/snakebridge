<p align="center">
  <img src="assets/snakebridge.svg" alt="SnakeBridge Logo">
</p>

# SnakeBridge

[![Hex.pm](https://img.shields.io/hexpm/v/snakebridge.svg)](https://hex.pm/packages/snakebridge)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/snakebridge)

Compile-time generator for type-safe Elixir bindings to Python libraries.

## Installation

Add SnakeBridge to your dependencies and configure Python libraries in your `mix.exs`:

```elixir
defmodule MyApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :my_app,
      version: "1.0.0",
      elixir: "~> 1.14",
      deps: deps(),
      python_deps: python_deps()  # Python libraries go here
    ]
  end

  defp deps do
    [
      {:snakebridge, "~> 0.7.9"}
    ]
  end

  # Define Python dependencies just like Elixir deps
  defp python_deps do
    [
      {:numpy, "1.26.0"},
      {:pandas, "2.0.0", include: ["DataFrame", "read_csv"]}
    ]
  end
end
```

The `python_deps` function mirrors how `deps` works - a list of tuples with the library name,
version, and optional configuration.

Then add runtime configuration in `config/runtime.exs`:

```elixir
import Config

# Auto-configure snakepit for snakebridge
SnakeBridge.ConfigHelper.configure_snakepit!()
```

## Quick Start

```elixir
# Generated wrappers work like native Elixir
{:ok, result} = Numpy.mean([1, 2, 3, 4])

# Optional Python arguments via keyword opts
{:ok, result} = Numpy.mean([[1, 2], [3, 4]], axis: 0)

# Runtime flags (idempotent caching, timeouts)
{:ok, result} = Numpy.mean([1, 2, 3], idempotent: true)
```

## Features

### Generated Wrappers

SnakeBridge generates Elixir modules that wrap Python libraries:

```elixir
# Python: numpy.mean(a, axis=None, dtype=None, keepdims=False)
# Generated: Numpy.mean(a, opts \\ [])

Numpy.mean([1, 2, 3])                      # Basic call
Numpy.mean([1, 2, 3], axis: 0)             # With Python kwargs
Numpy.mean([1, 2, 3], idempotent: true)    # With runtime flags
Numpy.reshape([1, 2, 3, 4], [[2, 2]], order: "C") # Extra positional args list
```

All wrappers accept:
- **Extra positional args**: `args` list appended after required parameters
- **Keyword options**: `opts` for Python kwargs and runtime flags (`idempotent`, `__runtime__`)

### Signature & Arity Model

SnakeBridge matches call-site arity against a manifest range so optional args and keyword
opts do not produce perpetual "missing" symbols. Required keyword-only parameters are
documented and validated at runtime.

When a Python signature is unavailable (common for C-extensions), SnakeBridge generates
variadic wrappers with convenience arities up to a configurable max (default 8):

```elixir
config :snakebridge, variadic_max_arity: 8
```

Python function and method names that are invalid in Elixir are sanitized (for example,
`class` → `py_class`). The manifest stores the Python↔Elixir mapping and runtime calls
use the original Python name. Common dunder methods map to idiomatic names (for example,
`__init__` → `new`, `__len__` → `length`).

### Class Constructors

Classes generate `new/N` matching their Python `__init__`:

```elixir
# Python: class Point:
#           def __init__(self, x, y): ...
# Generated: Geometry.Point.new(x, y, opts \\ [])

{:ok, point} = Geometry.Point.new(10, 20)
{:ok, x} = Geometry.Point.x(point)  # Attribute access
:ok = SnakeBridge.Runtime.release_ref(point)
```

### Class vs Submodule Resolution

Nested calls like `Lib.Foo.bar/…` are resolved automatically via introspection. SnakeBridge
checks whether `Foo` is a class attribute on the parent module first, and falls back to a
submodule when it is not. This means classes are detected without manual `include`.

### Instance Attributes

Read and write Python object attributes:

```elixir
# Get attribute
{:ok, value} = SnakeBridge.Runtime.get_attr(instance, "attribute_name")

# Set attribute
:ok = SnakeBridge.Runtime.set_attr(instance, "attribute_name", new_value)
```

### Module Attributes

Module-level constants and objects are exposed via generated zero-arity accessors or the
runtime API:

```elixir
{:ok, pi} = Math.pi()
{:ok, nan} = Numpy.nan()

# Or via the runtime helper
{:ok, pi} = SnakeBridge.Runtime.get_module_attr(Math, :pi)
```

### Dynamic Dispatch (No-Codegen)

Call Python functions and methods without generated wrappers:

```elixir
# Call a function by module path
{:ok, value} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [144])

# Create a ref and call methods dynamically
{:ok, ref} = SnakeBridge.Runtime.call_dynamic("pathlib", "Path", ["."])
{:ok, exists?} = SnakeBridge.Dynamic.call(ref, :exists, [])
{:ok, name} = SnakeBridge.Dynamic.get_attr(ref, :name)
{:ok, _} = SnakeBridge.Dynamic.set_attr(ref, :name, "snakebridge")
```

Use generated wrappers when you want compile-time arity checks, docs, and faster hot-path
calls. Use dynamic dispatch when symbols are discovered at runtime or when introspection
cannot see the module/class ahead of time.

Performance considerations: dynamic calls are string-based and skip codegen optimizations,
so prefer generated wrappers for frequently called functions.

### Session Lifecycle Management

SnakeBridge scopes Python object refs to sessions and releases them when the owning
process exits. Use `SessionContext.with_session/1` to bind a session to the current
process:

```elixir
SnakeBridge.SessionContext.with_session(fn ->
  {:ok, ref} = SnakeBridge.Runtime.call_dynamic("pathlib", "Path", ["."])
  {:ok, exists?} = SnakeBridge.Dynamic.call(ref, :exists, [])
end)
```

Refs created inside the block share the same `session_id`, so multiple calls can
chain on the same Python objects. The `SessionManager` monitors the owner process
and calls Python `release_session` when it dies. You can also release explicitly:

```elixir
:ok = SnakeBridge.SessionManager.release_session(session_id)
```

Pass explicit options with `SessionContext.with_session/2` when you need a
custom session id or metadata:

```elixir
SnakeBridge.SessionContext.with_session(session_id: "analytics", fn ->
  {:ok, ref} = SnakeBridge.Runtime.call_dynamic("pathlib", "Path", ["."])
  {:ok, _} = SnakeBridge.Dynamic.call(ref, :exists, [])
end)
```

Configuration options (environment variables):
- `SNAKEBRIDGE_REF_TTL_SECONDS` (default `0`, disabled) to enable time-based cleanup
- `SNAKEBRIDGE_REF_MAX` to cap in-memory refs per Python process

### Streaming Functions

Configure streaming functions to generate `*_stream` variants:

```elixir
# In mix.exs
{:llm, version: "1.0", streaming: ["generate", "complete"]}

# Generated variants:
LLM.generate(prompt)                              # Returns complete result
LLM.generate_stream(prompt, opts, callback)       # Streams chunks to callback

# Usage:
LLM.generate_stream("Hello", [], fn chunk ->
  IO.write(chunk)
end)
```

Streaming calls use Snakepit's server-side streaming RPC
`BridgeService.ExecuteStreamingTool`. Tools must be registered with
`supports_streaming: true` for streaming to work; the `ExecuteToolRequest.stream`
field alone is not sufficient.

### Generators and Iterators

Python generators and iterators are returned as `SnakeBridge.StreamRef` and implement
the `Enumerable` protocol for lazy iteration:

```elixir
{:ok, stream} = SnakeBridge.Runtime.call_dynamic("itertools", "count", [1])
Enum.take(stream, 5)
```

Performance considerations: each element is fetched over the runtime boundary. Prefer
batching (e.g., Python-side list construction) for large iterations, and use bounded
Enum operations (`Enum.take/2`, `Enum.reduce/3`) to limit round-trips.

### Protocol Integration (Refs)

Python refs implement Elixir protocols for smoother interop:

```elixir
{:ok, ref} = SnakeBridge.Runtime.call_dynamic("builtins", "range", [0, 3])

inspect(ref)          # Uses Python __repr__ / __str__
"Range: #{ref}"       # Uses Python __str__
Enum.count(ref)       # Calls __len__
Enum.map(ref, &(&1 * 2))
```

### Python Context Managers

Use `SnakeBridge.with_python/2` to safely call `__enter__` and `__exit__`:

```elixir
{:ok, file} = SnakeBridge.Runtime.call_dynamic("builtins", "open", ["output.txt", "w"])

SnakeBridge.with_python(file) do
  SnakeBridge.Dynamic.call(file, :write, ["hello\\n"])
end
```

The `context` variable inside the block is bound to the `__enter__` return value.

### Callbacks (Elixir → Python)

Elixir functions can be passed to Python as callbacks:

```elixir
callback = fn x -> x * 2 end
{:ok, stream} = SnakeBridge.Runtime.call_dynamic("builtins", "map", [callback, [1, 2, 3]])
Enum.to_list(stream)
```

Performance considerations: callbacks cross the boundary per invocation. Keep callback
work small or batch on the Python side when possible.

### Strict Mode for CI

Enable strict mode to verify generated code integrity:

```bash
# In CI
SNAKEBRIDGE_STRICT=1 mix compile
```

Strict mode verifies:
1. All used symbols are in the manifest
2. All generated files exist
3. Expected functions are present in generated files

### Documentation Conversion

Python docstrings are converted to ExDoc Markdown:

- NumPy style -> Markdown sections
- Google style -> Markdown sections
- Sphinx/Epytext styles supported
- RST math (``:math:`E=mc^2``) -> KaTeX (`$E=mc^2$`)

### Wire Schema (v1)

SnakeBridge tags non-JSON values with `__type__` and `__schema__` markers to keep
the Elixir/Python contract stable across versions. Atoms are encoded as tagged
values and decoded only when allowlisted:

```elixir
config :snakebridge, atom_allowlist: ["ok", "error"]
```

Python decodes tagged atoms to plain strings by default for compatibility with
most libraries. Opt in to Atom wrapper objects by setting:

```bash
SNAKEBRIDGE_ATOM_CLASS=true
```

Python results that are not JSON-serializable are automatically returned as
refs (e.g., `{"__type__": "ref", ...}`) so you can chain method calls on the
returned object. Each ref includes a `session_id` to keep ownership scoped
to the calling process.

### ML Error Translation

Python ML exceptions are translated to structured Elixir errors:

```elixir
# Shape mismatches with tensor dimensions
%SnakeBridge.Error.ShapeMismatchError{expected: [3, 4], actual: [4, 3]}

# Out of memory with device info
%SnakeBridge.Error.OutOfMemoryError{device: :cuda, available: 1024, requested: 2048}

# Dtype conflicts with casting guidance
%SnakeBridge.Error.DtypeMismatchError{expected: :float32, actual: :float64}
```

Use `SnakeBridge.ErrorTranslator.translate/1` for manual translation, or set
`error_mode` to translate on every runtime call:

```elixir
config :snakebridge, error_mode: :translated
```

Unknown Python exceptions are mapped dynamically into
`SnakeBridge.DynamicException.*` modules so you can rescue by type:

```elixir
config :snakebridge, error_mode: :raise_translated

try do
  SnakeBridge.Runtime.call_dynamic("builtins", "int", ["not-a-number"])
rescue
  e in SnakeBridge.DynamicException.ValueError ->
    IO.puts("Caught: #{Exception.message(e)}")
end
```

### Telemetry

The compile pipeline emits telemetry events:

```elixir
# Attach handler
:telemetry.attach("my-handler", [:snakebridge, :compile, :stop], fn _, measurements, _, _ ->
  IO.puts("Compiled #{measurements.symbols_generated} symbols")
end, nil)
```

Compile events:
- `[:snakebridge, :compile, :start|:stop|:exception]`
- `[:snakebridge, :compile, :scan, :stop]`
- `[:snakebridge, :compile, :introspect, :start|:stop]`
- `[:snakebridge, :compile, :generate, :stop]`
- `[:snakebridge, :docs, :fetch]`
- `[:snakebridge, :lock, :verify]`

Runtime events (forwarded from Snakepit):
- `[:snakebridge, :runtime, :call, :start|:stop|:exception]`

Telemetry metadata schema:
- Compile events include `library`, `phase`, and `details`.
- Runtime events include `library`, `function`, and `call_type`.

Breaking change: compile phase events now live under `[:snakebridge, :compile, ...]`
and share the unified metadata schema above.

### Wheel Variants

Hardware-specific wheels are configured via `config/wheel_variants.json`:

```json
{
  "packages": {
    "torch": {
      "variants": ["cpu", "cu118", "cu121", "cu124", "rocm5.7"]
    }
  },
  "cuda_mappings": {
    "12.1": "cu121",
    "12.4": "cu124"
  },
  "rocm_variant": "rocm5.7"
}
```

Override the file path or selection strategy if needed:

```elixir
config :snakebridge,
  wheel_config_path: "config/wheel_variants.json",
  wheel_strategy: SnakeBridge.WheelSelector.ConfigStrategy
```

## Configuration

### Python Dependencies (mix.exs)

```elixir
def project do
  [
    app: :my_app,
    deps: deps(),
    python_deps: python_deps()
  ]
end

defp python_deps do
  [
    # Simple: name and version
    {:numpy, "1.26.0"},

    # With options (3-tuple)
    {:pandas, "2.0.0",
      pypi_package: "pandas",
      extras: ["sql", "excel"],      # pip extras
      include: ["DataFrame", "read_csv", "read_json"],
      exclude: ["testing"],
      streaming: ["read_csv_chunked"],
      submodules: true},

    # Standard library (no version needed)
    {:json, :stdlib},
    {:math, :stdlib}
  ]
end
```

### Application Config (config/config.exs)

```elixir
config :snakebridge,
  # Paths
  generated_dir: "lib/snakebridge_generated",
  metadata_dir: ".snakebridge",
  scan_paths: ["lib"],
  scan_exclude: ["lib/generated"],

  # Behavior
  auto_install: :dev,      # :never | :dev | :always
  strict: false,           # or SNAKEBRIDGE_STRICT=1
  verbose: false,
  error_mode: :raw,        # :raw | :translated | :raise_translated
  atom_allowlist: ["ok", "error"]

# Advanced introspection config
config :snakebridge, :introspector,
  max_concurrency: 4,
  timeout: 30_000
```

### Runtime Config (config/runtime.exs)

SnakeBridge provides a configuration helper that automatically sets up Snakepit
with the correct Python executable, adapter, and PYTHONPATH. Add this to your
`config/runtime.exs`:

```elixir
import Config

# Auto-configure snakepit for snakebridge
SnakeBridge.ConfigHelper.configure_snakepit!()
```

This replaces ~30 lines of manual configuration and automatically:
- Finds the Python venv (in `.venv`, snakebridge dep location, or via `$SNAKEBRIDGE_VENV`)
- Configures the snakebridge adapter
- Sets up PYTHONPATH with snakepit and snakebridge priv directories

For custom pool sizes or explicit venv paths:

```elixir
SnakeBridge.ConfigHelper.configure_snakepit!(pool_size: 4, venv_path: "/path/to/venv")
```

Python adapter ref lifecycle (environment variables):

```bash
SNAKEBRIDGE_REF_TTL_SECONDS=3600
SNAKEBRIDGE_REF_MAX=10000
SNAKEBRIDGE_ATOM_CLASS=true
```

Python adapter protocol compatibility (environment variables):

```bash
# Strict by default. Set to 1/true/yes to accept legacy payloads without protocol metadata.
SNAKEBRIDGE_ALLOW_LEGACY_PROTOCOL=0
```

Protocol checks are strict by default. Ensure callers include `protocol_version` and
`min_supported_version` in runtime payloads (all `SnakeBridge.Runtime` helpers do this automatically).

## Mix Tasks

```bash
mix snakebridge.setup          # Install Python packages
mix snakebridge.setup --check  # Verify packages installed
mix snakebridge.verify         # Verify hardware compatibility
mix snakebridge.verify --strict # Fail on any mismatch
```

## Examples

See the `examples/` directory:

```bash
# Run all examples
./examples/run_all.sh

# Individual examples
cd examples/wrapper_args_example && mix run -e Demo.run
cd examples/class_constructor_example && mix run -e Demo.run
cd examples/streaming_example && mix run -e Demo.run
cd examples/strict_mode_example && mix run -e Demo.run
cd examples/universal_ffi_example && mix run -e Demo.run  # Universal FFI showcase
```

## Direct Runtime API

For dynamic calls when module/function names aren't known at compile time:

```elixir
# Direct call
{:ok, result} = SnakeBridge.call("math", "sqrt", [16])

# Dynamic call without codegen
{:ok, result} = SnakeBridge.Runtime.call_dynamic("math", "sqrt", [16])

# Streaming call
SnakeBridge.stream("llm", "generate", ["prompt"], [], fn chunk -> IO.write(chunk) end)

# Release refs when done
:ok = SnakeBridge.Runtime.release_ref(ref)
:ok = SnakeBridge.Runtime.release_session("session-id")
```

## Architecture

SnakeBridge is a compile-time code generator:

1. **Scan**: Find calls to configured library modules in your code
2. **Introspect**: Query Python for function/class signatures
3. **Generate**: Create Elixir wrapper modules with proper arities
4. **Lock**: Record environment for reproducibility

Runtime calls delegate to [Snakepit](https://hex.pm/packages/snakepit).

## Cross-Cutting Contract (Snakepit + Snakebridge)

### Wire Format for JSON Any Payloads

SnakeBridge uses a **custom gRPC Any convention**: `Any.value` contains raw UTF-8 JSON bytes (not protobuf-packed), with `type_url` set to `type.googleapis.com/google.protobuf.StringValue`.

**Reserved payload fields** (present in every call):

| Field | Type | Description |
|-------|------|-------------|
| `protocol_version` | int | Wire format version (currently `1`) |
| `min_supported_version` | int | Minimum accepted version (currently `1`) |
| `session_id` | string | Ref lifecycle and routing scope |
| `call_type` | string | `function`, `class`, `method`, `dynamic`, `get_attr`, `set_attr`, `module_attr`, `stream_next`, `helper` |
| `library` | string | Library name (e.g., `numpy`) |
| `python_module` | string | Full module path (e.g., `numpy.linalg`) |
| `function` | string | Function/method/class name |
| `args` | list | Positional arguments (encoded) |
| `kwargs` | dict | Keyword arguments (encoded) |

**Tagged type encoding** uses `__type__` and `__schema__` markers:

| Stability | Types |
|-----------|-------|
| **Stable** | `atom`, `tuple`, `set`, `bytes`, `datetime`, `date`, `time`, `special_float`, `ref`, `dict` |
| **Experimental** | `stream_ref`, `callback`, `complex` |

### Protocol Versioning

Compatibility is enforced **per-call** (not per-session). Both sides check:

- Caller's `protocol_version` >= adapter's `MIN_SUPPORTED_VERSION`
- Caller's `min_supported_version` <= adapter's `PROTOCOL_VERSION`

**Strict by default**. To accept legacy payloads without version fields:

```bash
SNAKEBRIDGE_ALLOW_LEGACY_PROTOCOL=1
```

On mismatch, `SnakeBridgeProtocolError` includes all four version values for diagnostics.

### Timeouts and Profiles

SnakeBridge provides configurable timeout defaults that are safer for ML/LLM workloads.

#### Per-Call Timeout Override

```elixir
# Explicit timeout (10 minutes)
Numpy.compute(data, __runtime__: [timeout: 600_000])

# Use a named profile
Transformers.generate(prompt, __runtime__: [timeout_profile: :ml_inference])

# For streaming operations
MyLib.stream_data(args, opts, callback, __runtime__: [stream_timeout: 3_600_000])
```

#### Built-in Timeout Profiles

| Profile | Timeout | Stream Timeout | Use Case |
|---------|---------|----------------|----------|
| `:default` | 2 min | - | Regular function calls |
| `:streaming` | 2 min | 30 min | Streaming operations |
| `:ml_inference` | 10 min | 30 min | LLM/ML inference |
| `:batch_job` | infinity | infinity | Long-running batch jobs |

#### Global Configuration

```elixir
config :snakebridge,
  runtime: [
    # Default profile for all calls
    timeout_profile: :default,

    # Override defaults
    default_timeout: 120_000,        # 2 minutes
    default_stream_timeout: 1_800_000, # 30 minutes

    # Per-library profile mapping
    library_profiles: %{
      "transformers" => :ml_inference,
      "torch" => :batch_job
    },

    # Custom profiles
    profiles: %{
      default: [timeout: 120_000],
      ml_inference: [timeout: 600_000, stream_timeout: 1_800_000],
      batch_job: [timeout: :infinity, stream_timeout: :infinity]
    }
  ]
```

#### Escape Hatch

Any other keys in `__runtime__` are forwarded directly to Snakepit:

```elixir
# Pass-through to Snakepit's advanced options
MyLib.func(args, __runtime__: [timeout: 60_000, pool: :my_pool])
```

### Operational Defaults

| Knob | Default | Config |
|------|---------|--------|
| gRPC max message size | 100 MB (send/receive) | Fixed |
| Session TTL | 3600s (1 hour) | `SessionStore` |
| Max sessions | 10,000 | `SessionStore` |
| Request timeout | 120s (2 min) | `runtime: [default_timeout:]` |
| Stream timeout | 30 min | `runtime: [default_stream_timeout:]` |
| Pool size | `System.schedulers_online() * 2` | `:snakepit` config |
| Heartbeat interval | 2s | HeartbeatConfig |
| Heartbeat timeout | 10s | HeartbeatConfig |
| Log level (Elixir) | `:error` | `config :snakepit, log_level:` |
| Log level (Python) | `error` | `SNAKEPIT_LOG_LEVEL` |
| Telemetry sampling | 1.0 (100%) | Runtime control |

## Requirements

- Elixir ~> 1.14
- Python 3.8+
- Snakepit ~> 0.8.8

## License

MIT
