<p align="center">
  <img src="assets/snakebridge.svg" alt="SnakeBridge Logo" width="200" height="200">
</p>

# SnakeBridge

[![Elixir](https://img.shields.io/badge/elixir-1.14+-purple.svg)](https://elixir-lang.org)
[![OTP](https://img.shields.io/badge/otp-25+-blue.svg)](https://www.erlang.org)
[![Hex.pm](https://img.shields.io/hexpm/v/snakebridge.svg)](https://hex.pm/packages/snakebridge)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-purple.svg)](https://hexdocs.pm/snakebridge)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/nshkrdotcom/snakebridge/blob/main/LICENSE)

Manifest-driven Python library integration for Elixir. Curate the functions you want, generate Elixir modules, and run them through Snakepit's gRPC runtime.

SnakeBridge is a small, declarative layer on top of [Snakepit](https://hex.pm/packages/snakepit): manifests are data, generation is dumb, and humans approve what gets exposed.

## Features

- Data-only JSON manifests for curated, stateless Python functions
- Built-in manifests for `sympy`, `pylatexenc`, and `math-verify`
- Manifest allowlist enforcement (explicit `allow_unsafe: true` to bypass)
- Loader for built-in + custom manifests (`priv/snakebridge/manifests`, `custom_manifests` globs)
- Runtime and compile-time generation (via `mix snakebridge.manifest.compile`)
- Auto-starts Snakepit pools on first real call (disable with `auto_start_snakepit: false`)
- Streaming support via `call_python_stream` and generated `*_stream` wrappers
- Introspection tooling: discover, gen, suggest, enrich, review, diff, check
- Per-library bridge serialization (bridges in `priv/python/bridges/`)
- Explicit instance lifecycle (`Runtime.release_instance/1`)
- Telemetry on runtime calls (`[:snakebridge, :call, ...]`)

## Installation

### 1. Add to mix.exs

```elixir
def deps do
  [
    {:snakebridge, "~> 0.3.1"},
    {:snakepit, "~> 0.7.0"}
  ]
end
```

### 2. Install Elixir deps

```bash
mix deps.get
```

### 3. Python setup (required for real Python execution)

SnakeBridge uses a Python adapter via Snakepit. For live Python calls, you need a venv and packages installed.

```bash
mix snakebridge.setup --venv .venv

# Export environment for runtime (or let SnakepitLauncher resolve it)
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
export PYTHONPATH=$(pwd)/priv/python:$(pwd)/priv/python/bridges:$(pwd)/deps/snakepit/priv/python:$PYTHONPATH
```

This installs:
- Snakepit core requirements (gRPC, protobuf, numpy, telemetry)
- SnakeBridge adapter
- Built-in manifest libs (sympy, pylatexenc, math-verify)

Docs:
- Python setup: `docs/PYTHON_SETUP.md`
- Example walkthrough: `examples/QUICKSTART.md`

## Quick Start (Built-in Manifests)

### Configure manifests

```elixir
# config/config.exs
config :snakebridge,
  load: [:sympy, :pylatexenc, :math_verify],
  custom_manifests: ["config/snakebridge/*.json"],
  compilation_mode: :runtime,
  auto_start_snakepit: true,
  allow_unsafe: false,
  python_path: ".venv/bin/python3",
  pool_size: 4
```

SnakeBridge loads configured manifests at application start (unless `compilation_mode: :compile_time`).

### Use the generated modules

```elixir
{:ok, roots} = SnakeBridge.SymPy.solve(%{expr: "x**2 - 1", symbol: "x"})
{:ok, nodes} = SnakeBridge.PyLatexEnc.parse(%{latex: "\\frac{1}{2}"})
{:ok, ok?} = SnakeBridge.MathVerify.verify(%{gold: "x**2", answer: "x*x"})
```

## Allowlist and Unsafe Calls

By default, SnakeBridge only allows calls that are defined in loaded manifests. The allowlist is populated when `SnakeBridge.Manifest.Loader` runs. If you generate modules manually, register the config first or pass `allow_unsafe: true`:

```elixir
{:ok, config} = SnakeBridge.Manifest.from_file("config/snakebridge/json.json")
SnakeBridge.Manifest.Registry.register_config(config)

SnakeBridge.Runtime.call_function("json", "dumps", %{obj: %{a: 1}}, allow_unsafe: true)
```

## Manifest Format (Simplified)

```json
{
  "name": "sympy",
  "python_module": "sympy",
  "python_path_prefix": "bridges.sympy_bridge",
  "version": "~> 1.13",
  "category": "math",
  "elixir_module": "SnakeBridge.SymPy",
  "pypi_package": "sympy",
  "description": "Symbolic mathematics",
  "status": "beta",
  "types": {
    "expr": "string",
    "symbol": "string"
  },
  "functions": [
    {"name": "solve", "args": ["expr", "symbol"], "returns": {"type": "list", "element_type": "string"}},
    {"name": "simplify", "args": ["expr"], "returns": "string"},
    {"name": "expand", "args": ["expr"], "returns": "string"}
  ]
}
```

Manifests live under `priv/snakebridge/manifests/`. The loader scans this directory automatically.

## Manifest Workflow

```bash
# Discover a library and generate a draft manifest
mix snakebridge.discover sympy --output priv/snakebridge/manifests/_drafts/sympy.json

# Generate a draft manifest from introspection
mix snakebridge.manifest.gen sympy --output priv/snakebridge/manifests/_drafts/sympy.json

# Or suggest a curated subset (heuristic)
mix snakebridge.manifest.suggest sympy --output priv/snakebridge/manifests/_drafts/sympy.json

# Enrich with docstrings + types (optionally cached schema)
mix snakebridge.manifest.enrich sympy --cache --cache-dir priv/snakebridge/schemas

# Review interactively
mix snakebridge.manifest.review sympy --introspect

# Validate and diff against live schema
mix snakebridge.manifest.validate priv/snakebridge/manifests/sympy.json
mix snakebridge.manifest.diff sympy

# Fail CI on drift
mix snakebridge.manifest.check --all
```

## Compile-Time Generation

```bash
# Generate Elixir source files
mix snakebridge.manifest.compile --load sympy,pylatexenc --output lib/snakebridge/generated

# Clean and recompile
mix snakebridge.manifest.clean --load sympy,pylatexenc
```

Enable compile-time loading:

```elixir
config :snakebridge, compilation_mode: :compile_time
```

## Streaming

Manifests can mark functions as streaming:

```elixir
%{name: "generate", python_path: "my.module.generate", streaming: true}
```

SnakeBridge will generate a `generate_stream/2` function and call the `call_python_stream` tool:

```elixir
MyLib.generate_stream(%{prompt: "Hello"})
|> Enum.each(&IO.inspect/1)
```

If you have a custom streaming tool, set `streaming_tool` in the manifest and the wrapper will call it directly.

## Examples

See `examples/README.md` for a full list and expected outputs. A quick way to run them all:

```bash
./examples/run_all.sh
```

Example scripts:
- `examples/manifest_sympy.exs`
- `examples/manifest_pylatexenc.exs`
- `examples/manifest_math_verify.exs`

## Testing

```bash
# Mock tests (no Python)
mix test

# Real Python integration tests
mix test --only real_python
```

## Built-in Manifests

- `sympy` -> `SnakeBridge.SymPy`
- `pylatexenc` -> `SnakeBridge.PyLatexEnc`
- `math_verify` -> `SnakeBridge.MathVerify`

List them:

```bash
mix snakebridge.manifests
```

## Creating a New Integration

Adding a new Python library integration requires **1-2 files**:

### Minimal: Manifest Only (1 file)

If the library returns JSON-serializable types (strings, numbers, lists, dicts), you only need a manifest:

```bash
# priv/snakebridge/manifests/my_library.json
```

```json
{
  "name": "my_library",
  "python_module": "my_library",
  "python_path_prefix": "my_library",
  "elixir_module": "SnakeBridge.MyLibrary",
  "pypi_package": "my-library",
  "description": "My library description",
  "status": "experimental",
  "functions": [
    {"name": "do_something", "args": ["input"], "returns": "string"}
  ]
}
```

Then add to config and use:

```elixir
config :snakebridge, load: [:my_library]

# After restart:
{:ok, result} = SnakeBridge.MyLibrary.do_something(%{input: "hello"})
```

### With Bridge: Custom Serialization (2 files)

If the library returns complex objects (custom classes, numpy arrays, etc.), add a bridge:

```bash
# priv/python/bridges/my_library_bridge.py
```

```python
def do_something(input):
    result = my_library.do_something(input)
    return str(result)  # Or custom serialization
```

Update manifest to point to bridge:

```json
{
  "python_path_prefix": "bridges.my_library_bridge",
  ...
}
```

### Files Required

| Scenario | Manifest | Bridge | Total |
|----------|----------|--------|-------|
| Simple library (JSON-safe returns) | 1 | 0 | **1 file** |
| Complex library (custom objects) | 1 | 1 | **2 files** |

No changes needed to core SnakeBridge code, `_index.json`, catalogs, or adapters.

## Mix Tasks

```bash
# Setup
mix snakebridge.setup --venv .venv

# Manifests
mix snakebridge.manifest.validate priv/snakebridge/manifests/sympy.json
mix snakebridge.manifest.check --all
mix snakebridge.manifest.install --load sympy,pylatexenc,math_verify --venv .venv --include_core

# Discovery
mix snakebridge.discover sympy --output priv/snakebridge/manifests/_drafts/sympy.json
```
