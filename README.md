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

- **Automated adapter creation** via `mix snakebridge.adapter.create` (two-phase: deterministic + agent fallback)
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

```elixir
# mix.exs
def deps do
  [
    {:snakebridge, "~> 0.3.2"},
    {:snakepit, "~> 0.7.0"}
  ]
end
```

```bash
mix deps.get
```

**That's it.** Python environments are created and managed automatically on first use. No manual venv setup, no exports, no pip commands needed.

## Quick Start

```elixir
# Use built-in manifests immediately - no config needed
{:ok, roots} = SnakeBridge.SymPy.solve(%{expr: "x**2 - 1", symbol: "x"})
{:ok, nodes} = SnakeBridge.PyLatexEnc.parse(%{latex: "\\frac{1}{2}"})
{:ok, ok?} = SnakeBridge.MathVerify.verify(%{gold: "x**2", answer: "x*x"})
```

Built-in manifests (sympy, pylatexenc, math_verify) are auto-loaded. Python packages are auto-installed on first use.

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

## Creating Adapters (Zero-Friction)

Add any Python library with a single command:

```bash
mix snakebridge.adapter.create chardet
```

Then immediately use it:

```elixir
{:ok, result} = SnakeBridge.Chardet.detect(%{
  byte_str: Base.encode64("Hello, 世界!"),
  should_rename_legacy: false
})
# => {:ok, %{"confidence" => 0.75, "encoding" => "utf-8", "language" => ""}}
```

**That's it.** No venv setup, no pip install, no config editing. Everything is automatic:

- Python venv created on first use
- Pip packages installed automatically
- Manifests auto-discovered and loaded
- PYTHONPATH configured internally

### How It Works

The adapter creator uses a **two-phase approach**:

1. **Phase 1: Deterministic** (fast, free)
   - Introspects the Python library
   - Filters to stateless functions
   - Generates manifest + bridge
   - Installs pip package

2. **Phase 2: Agent Fallback** (if needed)
   - Falls back to AI agent if Phase 1 fails
   - Requires `claude_agent_sdk` or `codex_sdk`

### Options

```bash
mix snakebridge.adapter.create chardet              # From PyPI
mix snakebridge.adapter.create https://github.com/user/repo  # From GitHub
mix snakebridge.adapter.create chardet --max-functions 10    # Limit functions
mix snakebridge.adapter.create chardet --agent               # Force AI agent
mix snakebridge.adapter.create --status                      # Show backends
```

## Creating Integrations Manually

For full control, create the files manually:

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

If the library returns complex objects (custom classes, bytes, etc.), add a bridge:

```bash
# priv/python/bridges/my_library_bridge.py
```

```python
import base64
import my_library

def do_something(input):
    result = my_library.do_something(input)
    return _serialize(result)

def _serialize(obj):
    if obj is None:
        return None
    if isinstance(obj, (str, int, float, bool)):
        return obj
    if isinstance(obj, bytes):
        return base64.b64encode(obj).decode('ascii')
    if isinstance(obj, (list, tuple)):
        return [_serialize(x) for x in obj]
    if isinstance(obj, dict):
        return {str(k): _serialize(v) for k, v in obj.items()}
    return str(obj)
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

No changes needed to core SnakeBridge code.

## Mix Tasks

```bash
# Setup
mix snakebridge.setup --venv .venv

# Adapter Creation (NEW)
mix snakebridge.adapter.create https://github.com/user/repo  # From GitHub
mix snakebridge.adapter.create package_name                  # From PyPI
mix snakebridge.adapter.create package_name --agent          # Force agent mode
mix snakebridge.adapter.create --status                      # Show backends

# Manifests
mix snakebridge.manifest.validate priv/snakebridge/manifests/sympy.json
mix snakebridge.manifest.check --all
mix snakebridge.manifest.install --load sympy,pylatexenc,math_verify --venv .venv --include_core

# Discovery
mix snakebridge.discover sympy --output priv/snakebridge/manifests/_drafts/sympy.json
```
