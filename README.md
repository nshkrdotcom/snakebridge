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
    {:snakebridge, "~> 0.7.0",
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

Numpy.mean([1, 2, 3])                    # Basic call
Numpy.mean([1, 2, 3], axis: 0)           # With Python kwargs
Numpy.mean([1, 2, 3], idempotent: true)  # With runtime flags
```

All wrappers accept `opts` for:
- **Python kwargs**: Passed to the Python function
- **Runtime flags**: `idempotent`, `__runtime__`, `__args__`

### Class Constructors

Classes generate `new/N` matching their Python `__init__`:

```elixir
# Python: class Point:
#           def __init__(self, x, y): ...
# Generated: Geometry.Point.new(x, y, opts \\ [])

{:ok, point} = Geometry.Point.new(10, 20)
{:ok, x} = Geometry.Point.x(point)  # Attribute access
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
- RST math (``:math:`E=mc^2``) -> KaTeX (`$E=mc^2$`)

### Telemetry

The compile pipeline emits telemetry events:

```elixir
# Attach handler
:telemetry.attach("my-handler", [:snakebridge, :compile, :stop], fn _, measurements, _, _ ->
  IO.puts("Compiled #{measurements.symbols_generated} symbols")
end, nil)
```

Events:
- `[:snakebridge, :compile, :start]`
- `[:snakebridge, :compile, :stop]`
- `[:snakebridge, :compile, :exception]`

## Configuration

```elixir
# mix.exs
{:snakebridge, "~> 0.7.0",
  libraries: [
    # Simple: name and version
    {:numpy, "1.26.0"},

    # Full options
    {:pandas,
      version: "2.0.0",
      pypi_package: "pandas",
      include: ["DataFrame", "read_csv", "read_json"],
      exclude: ["testing"],
      streaming: ["read_csv_chunked"],
      submodules: true}
  ],
  generated_dir: "lib/python_bindings",
  metadata_dir: ".snakebridge"
}

# config/config.exs
config :snakebridge,
  auto_install: :dev,      # :never | :dev | :always
  strict: false,           # or SNAKEBRIDGE_STRICT=1
  verbose: false
```

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
- Snakepit ~> 0.8.1

## License

MIT
