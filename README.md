<p align="center">
  <img src="assets/snakebridge.svg" alt="SnakeBridge Logo">
</p>

# SnakeBridge

[![Hex.pm](https://img.shields.io/hexpm/v/snakebridge.svg)](https://hex.pm/packages/snakebridge)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/snakebridge)

Compile-time generator for type-safe Elixir bindings to Python libraries.

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:snakebridge, "~> 0.7.2",
      libraries: [
        {:numpy, "1.26.0"},
        {:pandas, version: "2.0.0", include: ["DataFrame", "read_csv"]}
      ]}
  ]
end
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

### Instance Attributes

Read and write Python object attributes:

```elixir
# Get attribute
{:ok, value} = SnakeBridge.Runtime.get_attr(instance, "attribute_name")

# Set attribute
:ok = SnakeBridge.Runtime.set_attr(instance, "attribute_name", new_value)
```

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
- `[:snakebridge, :scan, :stop]`
- `[:snakebridge, :introspect, :start|:stop]`
- `[:snakebridge, :generate, :stop]`
- `[:snakebridge, :docs, :fetch]`
- `[:snakebridge, :lock, :verify]`

Runtime events (forwarded from Snakepit):
- `[:snakebridge, :runtime, :call, :start|:stop|:exception]`

## Configuration

```elixir
# mix.exs
{:snakebridge, "~> 0.7.2",
  libraries: [
    # Simple: name and version
    {:numpy, "1.26.0"},

    # Full options
    {:pandas,
      version: "2.0.0",
      pypi_package: "pandas",
      extras: ["sql", "excel"],      # pip extras
      include: ["DataFrame", "read_csv", "read_json"],
      exclude: ["testing"],
      streaming: ["read_csv_chunked"],
      submodules: true}
  ],
  generated_dir: "lib/python_bindings",
  metadata_dir: ".snakebridge",
  scan_paths: ["lib"],               # Paths to scan for usage
  scan_exclude: ["lib/generated"]    # Patterns to exclude
}

# config/config.exs
config :snakebridge,
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

Python adapter ref lifecycle (environment variables):

```bash
SNAKEBRIDGE_REF_TTL_SECONDS=3600
SNAKEBRIDGE_REF_MAX=10000
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
```

## Direct Runtime API

For dynamic calls when module/function names aren't known at compile time:

```elixir
# Direct call
{:ok, result} = SnakeBridge.call("math", "sqrt", [16])

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

## Requirements

- Elixir ~> 1.14
- Python 3.8+
- Snakepit ~> 0.8.3

## License

MIT
