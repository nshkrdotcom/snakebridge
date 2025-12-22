<p align="center">
  <img src="assets/snakebridge.svg" alt="SnakeBridge Logo" width="200" height="200">
</p>

# SnakeBridge

[![Elixir](https://img.shields.io/badge/elixir-1.14+-purple.svg)](https://elixir-lang.org)
[![OTP](https://img.shields.io/badge/otp-25+-blue.svg)](https://www.erlang.org)
[![Hex.pm](https://img.shields.io/hexpm/v/snakebridge.svg)](https://hex.pm/packages/snakebridge)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-purple.svg)](https://hexdocs.pm/snakebridge)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/nshkrdotcom/snakebridge/blob/main/LICENSE)

**Configuration-driven Python library integration for Elixir** - Bridge Elixir to the Python ML ecosystem with zero manual wrapper code.

SnakeBridge is a metaprogramming framework that automatically generates type-safe Elixir modules from declarative configurations, enabling seamless integration with any Python library. Built on [Snakepit](https://hex.pm/packages/snakepit) for high-performance Python orchestration.

## Features

✨ **Zero-Code Integration** - Write configuration, not wrappers
🔐 **Type Safety** - Automatic Python → Elixir typespec generation with Dialyzer integration
⚡ **Hybrid Compilation** - Runtime in dev (hot reload), compile-time in production (optimized)
🎯 **Smart Caching** - Git-style schema diffing with incremental regeneration
🔄 **Bidirectional Tools** - Export Elixir functions to Python seamlessly
🔁 **Streaming Pipelines** - Real-time gRPC streaming with chunk callbacks
📊 **Built-in Telemetry** - Comprehensive observability with `:telemetry` events
🧪 **Property-Based Testing** - Auto-generate test suites from schemas
🛠️ **LSP Integration** - Config authoring with autocomplete and diagnostics
🌉 **Protocol-Driven** - Extensible architecture supporting multiple backends

## Installation

### 1. Add to mix.exs

```elixir
def deps do
  [
    {:snakebridge, "~> 0.2.3"},
    {:snakepit, "~> 0.6.7"}  # Required runtime
  ]
end
```

### 2. Install Elixir dependencies

```bash
mix deps.get
```

### 3. ⚠️ Python Environment Setup (REQUIRED for real Python execution)

**IMPORTANT**: SnakeBridge tests use mocks by default (no Python needed). For real Python execution, you **MUST** set up a Python virtual environment.

**Why venv?** Modern systems (Ubuntu 24.04+, Debian 12+) prevent system-wide pip installs (PEP 668). Virtual environments are now mandatory, not optional.

#### Quick Setup (Recommended)

```bash
# From project root - creates venv and installs all dependencies
./scripts/setup_python.sh
```

This automatically:
- Creates `.venv/` if it doesn't exist
- Installs dependencies: `grpcio`, `protobuf`, `numpy`
- Detects and uses existing Snakepit venv if available

#### Manual Setup

```bash
# Create virtual environment
python3 -m venv .venv

# Install Snakepit dependencies
.venv/bin/pip install -r deps/snakepit/priv/python/requirements.txt

# Install SnakeBridge adapter
cd priv/python
../../.venv/bin/pip install -e .
cd ../..

# Configure Snakepit to use venv Python
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
```

#### For Users (Installing SnakeBridge as a dependency)

```bash
# Run setup script from your project
./deps/snakebridge/scripts/setup_python.sh

# Or manually:
cd deps/snakebridge/priv/python
python3 -m venv .venv
.venv/bin/pip install -e .
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
```

#### Verify Python Setup

```bash
# Check dependencies
.venv/bin/python3 -c "import grpc; print('✓ gRPC installed')"
.venv/bin/python3 -c "from snakebridge_adapter.adapter import SnakeBridgeAdapter; print('✓ Adapter ready')"
```

### 4. Verify installation

```bash
# Mock tests (no Python needed)
mix test

# Real Python integration tests
# SNAKEPIT_PYTHON optional: tests auto-fall back to ./.venv/bin/python3 or system python3
mix test --only real_python

# Real Python tests start a Snakepit pool automatically; they will fail fast if no Python is available.
```

**That's it!** Start using SnakeBridge.

> 📘 **Documentation Links**:
> - **Detailed Python setup guide**: [docs/PYTHON_SETUP.md](docs/PYTHON_SETUP.md)
> - **Example quick start**: [examples/QUICKSTART.md](examples/QUICKSTART.md)
> - **Test environment setup**: [test/integration/README.md](test/integration/README.md)
> - **Snakepit documentation**: See `deps/snakepit/README.md` after running `mix deps.get`

### Or Just Run Examples

The fastest way to see SnakeBridge:

```bash
# Mock demo (no Python needed - works immediately)
mix run examples/api_demo.exs

# Live Python examples (requires SNAKEPIT_PYTHON set)
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
elixir examples/live_demo.exs       # Built-in json module via Snakepit
elixir examples/numpy_live.exs      # NumPy scientific computing
elixir examples/genai_streaming.exs # Full streaming tool demo
```

Examples using `Mix.install` (like `live_demo.exs`) auto-configure Python via `example_helpers.exs`.

## Quick Start

### Try It Now (Zero Setup)

```bash
# See SnakeBridge in action
mix run examples/api_demo.exs
```

Shows configuration, code generation, type system - all working immediately.

### Live Python Examples

```bash
# JSON (built-in, no install)
elixir examples/live_demo.exs

# NumPy (auto-installs if needed)
elixir examples/numpy_live.exs

# Streaming (GenAI adapter)
elixir examples/genai_streaming.exs
```

**These just work** - auto-install dependencies, configure Snakepit, run live Python.

---

## What You Can Do

SnakeBridge can generate type-safe Elixir wrappers for:

✅ **Python Classes** - Full OOP support with instance management
✅ **Module-Level Functions** - Stateless function calls (added in v0.2.1)
✅ **Streaming Tools** - Bidirectional streaming callbacks (refined in v0.2.3!)
✅ **Mixed Integration** - Classes and functions from the same library

### Streaming Tools (v0.2.3)

SnakeBridge can now drive Python streams end-to-end with chunk callbacks:

```elixir
session_id = "demo:#{System.unique_integer([:positive])}"

SnakeBridge.Runtime.execute_stream(
  session_id,
  "stream_progress",
  %{"steps" => 5},
  fn chunk ->
    IO.inspect(chunk, label: "Chunk")
  end
)
```

**Highlights:**
- Powered by Snakepit v0.6.4's fixed streaming executor
- Works with adapters that expose streaming tools (GenAI, Showcase, custom)
- Automatic heartbeats + progress metadata included in each chunk

See `examples/genai_streaming.exs` or `examples/test_streaming_simple.exs` for a complete walkthrough.

### Function Generation

Call any Python function directly from Elixir:

```elixir
# Discover and generate
{:ok, schema} = SnakeBridge.discover("json")
config = SnakeBridge.Discovery.schema_to_config(schema, python_module: "json")
{:ok, [json_module]} = SnakeBridge.generate(config)

# Call Python functions - no instances needed!
{:ok, json_string} = json_module.dumps(%{obj: %{hello: "world", value: 42}})
# => "{\"hello\": \"world\", \"value\": 42}"

{:ok, data} = json_module.loads(%{s: json_string})
# => %{"hello" => "world", "value" => 42}
```

**Key Features:**
- **Stateless** - No instance creation, direct function calls
- **Type-safe** - Full typespec generation from Python signatures
- **Zero boilerplate** - Auto-generated from discovery
- **Works with any library** - json, numpy, requests, etc.

**Example: NumPy Math Functions**

```elixir
# Discover NumPy (626 functions!)
{:ok, schema} = SnakeBridge.discover("numpy")

# Generate wrappers for mathematical functions
config = SnakeBridge.Discovery.schema_to_config(schema, python_module: "numpy")
{:ok, modules} = SnakeBridge.generate(config)

# Call NumPy functions directly
numpy_module = Enum.find(modules, &function_exported?(&1, :mean, 2))
{:ok, result} = numpy_module.mean(%{a: [1, 2, 3, 4, 5]})
# => 3.0
```

Complex dtypes (`complex64` / `complex128`) are serialized as `%{real: float, imag: float}` per element in the returned `data` structure.

See `examples/live_demo.exs` for a complete working example.

---

## Using SnakeBridge

### 1. Discover a Python Library

```bash
# Auto-generate configuration from introspection
mix snakebridge.discover numpy --output config/snakebridge/numpy.exs
```

### 2. Review & Customize Configuration

```elixir
# config/snakebridge/dspy.exs
use SnakeBridge.Config

config do
  %SnakeBridge.Config{
    python_module: "dspy",
    version: "2.5.0",

    # Python classes (OOP)
    classes: [
      %{
        python_path: "dspy.Predict",
        elixir_module: DSPy.Predict,
        constructor: %{args: %{signature: {:required, :string}}},
        methods: [
          %{name: "__call__", elixir_name: :call, streaming: false}
        ]
      }
    ],

    # Module-level functions (available since v0.2.1)
    functions: [
      %{
        name: "configure",
        python_path: "dspy.settings.configure",
        elixir_name: :configure
      }
    ]
  }
end
```

### 3. Use Auto-Generated Modules

```elixir
# Modules are generated at compile-time (prod) or runtime (dev)

# Call module-level functions (stateless)
DSPy.Settings.configure(%{lm: lm_config})

# Create class instances and call methods
{:ok, predictor} = DSPy.Predict.create(%{signature: "question -> answer"})
{:ok, result} = DSPy.Predict.call(predictor, %{question: "What is SnakeBridge?"})

# %{answer: "A configuration-driven Python integration framework..."}
```

## Example: DSPy Integration

```elixir
# Configure DSPy language model (function call - no instance!)
{:ok, lm} = DSPy.LM.OpenAI.create(%{model: "gpt-4", api_key: api_key})
DSPy.Settings.configure(%{lm: lm})

# Use Chain of Thought with streaming
{:ok, cot} = DSPy.ChainOfThought.create("question -> reasoning, answer")
{:ok, stream} = DSPy.ChainOfThought.think(cot, %{question: "Explain quantum computing"})

for {:chunk, data} <- stream do
  IO.write(data)
end

# Optimize with BootstrapFewShot
{:ok, optimizer} = DSPy.Optimizers.BootstrapFewShot.create(%{
  metric: &accuracy/2,
  max_bootstrapped_demos: 4
})
{:ok, optimized} = DSPy.Optimizers.BootstrapFewShot.compile(optimizer, program, trainset)
```

## Configuration

```elixir
# config/config.exs
import Config

config :snakebridge,
  # Compilation strategy: :auto, :compile_time, or :runtime
  compilation_strategy: :auto,  # Auto = dev uses runtime, prod uses compile_time

  # Cache settings
  cache_path: "priv/snakebridge/cache",
  cache_enabled: true,

  # Telemetry
  telemetry_enabled: true,
  telemetry_prefix: [:snakebridge]
```

## Advanced Features

### Configuration Composition

```elixir
# Reusable mixin
defmodule BasePredictorMixin do
  def mixin do
    %{
      telemetry: %{enabled: true},
      timeout: 30_000,
      result_transform: &MyApp.Transforms.prediction/1
    }
  end
end

# Use in config
%{
  python_path: "dspy.Predict",
  mixins: [BasePredictorMixin],
  # Mixin fields are merged with local config
}
```

### Bidirectional Tool Calling

```elixir
# Export Elixir functions to Python
bidirectional_tools: %{
  enabled: true,
  export_to_python: [
    {MyApp.Validators, :validate_reasoning, 1, "elixir_validate"},
    {MyApp.Metrics, :track_prediction, 2, "elixir_track"}
  ]
}
```

```python
# In Python code, call Elixir functions
validation = elixir_validate(reasoning)
if not validation["valid"]:
    reasoning = retry_with_feedback(validation["feedback"])
```

### Type Safety

```elixir
# Python type hints → Elixir typespecs
# Python: def predict(signature: str, inputs: dict[str, Any]) -> dict[str, Any]:

# Generated Elixir:
@spec predict(String.t(), map()) :: {:ok, map()} | {:error, term()}
def predict(signature, inputs, opts \\ [])
```

## Documentation

- **[Getting Started Guide](https://hexdocs.pm/snakebridge/getting_started.html)** - Comprehensive tutorial
- **[API Reference](https://hexdocs.pm/snakebridge)** - Complete function documentation
- **[Configuration Schema](https://hexdocs.pm/snakebridge/SnakeBridge.Config.html)** - All config options
- **[Type System](https://hexdocs.pm/snakebridge/SnakeBridge.TypeSystem.html)** - Python ↔ Elixir type mapping
- **[Examples](https://github.com/nshkrdotcom/snakebridge/tree/main/examples)** - Working integrations

## Mix Tasks

```bash
# Discover Python library schema
mix snakebridge.discover <module> [--output path] [--depth N]

# Validate configurations
mix snakebridge.validate

# Show diff between cached and current schema
mix snakebridge.diff <integration_id>

# Generate modules from config
mix snakebridge.generate [integration_ids...]

# Clean caches
mix snakebridge.clean
```

## Testing

```bash
# Run all tests
mix test

# Run with coverage
mix coveralls
mix coveralls.html

# Run specific test categories
mix test test/unit              # Fast unit tests
mix test --only integration     # Integration tests
mix test test/property          # Property-based tests

# Quality checks
mix quality                     # Format + Credo + Dialyzer
```

## Architecture

SnakeBridge is built on a six-layer architecture:

```
┌─────────────────────────────────────┐
│  6. Developer Tools                 │  Mix tasks, LSP, IEx helpers
├─────────────────────────────────────┤
│  5. Generated Modules               │  Type-safe wrappers, docs, tests
├─────────────────────────────────────┤
│  4. Code Generation Engine          │  Macros, templates, optimization
├─────────────────────────────────────┤
│  3. Schema & Type System            │  Cache, inference, composition
├─────────────────────────────────────┤
│  2. Discovery & Introspection       │  gRPC protocol, Python agent
├─────────────────────────────────────┤
│  1. Execution Runtime               │  Snakepit, sessions, telemetry
└─────────────────────────────────────┘
```

See [Architecture Guide](https://hexdocs.pm/snakebridge/architecture.html) for details.

## Roadmap

### v0.1.0 (Current)
- [x] Core config schema
- [x] Basic code generation
- [x] Type system mapper
- [x] Discovery & introspection
- [ ] DSPy integration (proof-of-concept)

### v0.2.0
- [ ] Streaming support (gRPC)
- [ ] Hybrid compilation mode
- [ ] Configuration composition
- [ ] LSP server for configs

### v0.3.0
- [ ] LangChain integration
- [ ] Transformers integration
- [ ] Auto-generated test suites
- [ ] Performance optimizations

### v1.0.0
- [ ] Production-ready
- [ ] Comprehensive documentation
- [ ] 90%+ test coverage
- [ ] Community integrations

## Performance

| Operation | Overhead |
|-----------|----------|
| Instance creation | +4% |
| Method calls | +5% |
| Streaming | +2% |

**Negligible overhead** thanks to compile-time optimization.

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](https://github.com/nshkrdotcom/snakebridge/blob/main/CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests (`mix test`)
4. Ensure quality checks pass (`mix quality`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](https://github.com/nshkrdotcom/snakebridge/blob/main/LICENSE) file for details.

Copyright (c) 2025 nshkrdotcom

## Acknowledgments

- Built on [Snakepit](https://hex.pm/packages/snakepit) for Python orchestration
- Inspired by the need for seamless Elixir-Python ML integration
- Special thanks to the Elixir and Python communities

---

**Made with ❤️ by [nshkrdotcom](https://github.com/nshkrdotcom)**
