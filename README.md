# SnakeBridge

[![Elixir](https://img.shields.io/badge/elixir-1.14+-purple.svg)](https://elixir-lang.org)
[![Hex.pm](https://img.shields.io/hexpm/v/snakebridge.svg)](https://hex.pm/packages/snakebridge)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Generate type-safe Elixir bindings for Python libraries. SnakeBridge introspects Python modules and generates Elixir adapter code with full `@spec` declarations and documentation.

Built on [Snakepit](https://hex.pm/packages/snakepit) for Python runtime management.

## How It Works

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Python Module  │────>│  mix snakebridge │────>│  Elixir Adapter │
│  (e.g., json)   │     │      .gen        │     │  (json/*.ex)    │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                              │
                    Introspects Python:
                    - Function signatures
                    - Type annotations
                    - Docstrings
                    - Classes
```

**SnakeBridge generates source files, not runtime code.** The generated `.ex` files are committed to YOUR project and compiled like any other Elixir code.

## Installation

```elixir
# mix.exs
def deps do
  [
    {:snakebridge, "~> 0.4.0"}
  ]
end
```

## Quick Start

### 1. Generate an Adapter

```bash
$ mix snakebridge.gen json

Introspecting Python library: json...
  Found 4 functions in 1 namespaces
  Found 3 classes with 9 methods

Generating Elixir adapters...
  Writing lib/snakebridge/adapters/json/_meta.ex
  Writing lib/snakebridge/adapters/json/json.ex
  Writing lib/snakebridge/adapters/json/classes/json_decoder.ex
  ...

Success! Generated json adapter:
  Path: lib/snakebridge/adapters/json/
  Module: Json
  Functions: 4
  Classes: 3

Quick start:
  iex> alias Json
  iex> Json.dump(...)

Discovery:
  iex> Json.__functions__()
  iex> h Json
```

### 2. Use the Generated Module

```elixir
# The generated adapter is now available
alias Json

# Discover what's available
Json.__functions__()
# => [{:dump, 12, Json, "Serialize obj..."}, {:dumps, 11, Json, "..."}, ...]

Json.__search__("serialize")
# => [{:dump, 12, Json, "Serialize..."}, {:dumps, 11, Json, "Serialize..."}]

# Call Python functions
{:ok, result} = Json.dumps(my_data, false, true, true, true, nil, nil, nil, nil, nil, false)
```

## Generated File Structure

For a Python module like `json`, SnakeBridge generates a **directory structure**:

```
lib/snakebridge/adapters/json/
├── _meta.ex                    # Discovery functions
├── json.ex                     # Main module with functions
└── classes/
    ├── json_decoder.ex         # JSONDecoder class
    ├── json_encoder.ex         # JSONEncoder class
    └── json_decode_error.ex    # JSONDecodeError class
```

### Main Module (`json.ex`)

```elixir
defmodule Json do
  @moduledoc "JSON (JavaScript Object Notation) encoder/decoder..."
  use SnakeBridge.Adapter

  # Discovery functions (delegated to Meta)
  defdelegate __functions__, to: Json.Meta, as: :functions
  defdelegate __classes__, to: Json.Meta, as: :classes
  defdelegate __search__(query), to: Json.Meta, as: :search

  @doc "Serialize obj to a JSON formatted str..."
  @spec dumps(any(), any(), ...) :: any()
  @python_function "dumps"
  def dumps(obj, skipkeys, ...) do
    __python_call__("dumps", [obj, skipkeys, ...])
  end
end
```

### Meta Module (`_meta.ex`)

```elixir
defmodule Json.Meta do
  @moduledoc false

  @functions [
    {:dump, 12, Json, "Serialize obj as a JSON formatted stream..."},
    {:dumps, 11, Json, "Serialize obj to a JSON formatted str..."},
    {:load, 8, Json, "Deserialize fp to a Python object..."},
    {:loads, 8, Json, "Deserialize s to a Python object..."}
  ]

  def functions, do: @functions
  def classes, do: @classes
  def search(query), do: # filters functions by name/doc
end
```

## Discovery Functions

Every generated module includes discovery helpers:

```elixir
# List all functions with their arities and documentation
Json.__functions__()
# => [{:dump, 12, Json, "Serialize obj..."}, ...]

# List all classes
Json.__classes__()
# => [{Json.JSONDecoder, "Simple JSON decoder..."}, ...]

# Search functions by name or documentation
Json.__search__("serialize")
# => [{:dump, 12, Json, "Serialize obj..."}, {:dumps, 11, Json, "..."}]

# Standard IEx help works
iex> h Json.dumps
```

## Generator Options

```bash
mix snakebridge.gen <library> [options]

Options:
  --output <path>      Output directory (default: lib/snakebridge/adapters/<lib>/)
  --module <name>      Custom Elixir module name (default: CamelCase of library)
  --force              Remove existing and regenerate
  --functions <list>   Comma-separated list of functions to include
  --exclude <list>     Comma-separated list of functions to exclude
```

### Examples

```bash
# Generate only specific functions
mix snakebridge.gen numpy --functions array,zeros,ones,linspace

# Exclude certain functions
mix snakebridge.gen os --exclude system,exec,popen

# Generate to custom location with custom module
mix snakebridge.gen requests --output lib/my_app/http/ --module MyApp.Http

# Regenerate existing library
mix snakebridge.gen json --force
```

## Mix Tasks

```bash
# Generate adapter for a Python library
mix snakebridge.gen <library>

# List all generated adapters
mix snakebridge.list

# Show info about a generated adapter
mix snakebridge.info <library>

# Remove a generated adapter
mix snakebridge.clean <library>
```

## Type System

SnakeBridge handles the impedance mismatch between Python and Elixir types using tagged JSON serialization:

| Python Type | Elixir Type | Serialization |
|-------------|-------------|---------------|
| `None` | `nil` | Direct |
| `bool` | `boolean()` | Direct |
| `int` | `integer()` | Direct |
| `float` | `float()` | Direct |
| `str` | `String.t()` | Direct |
| `list` | `list()` | Direct |
| `dict` | `map()` | Direct |
| `tuple` | `tuple()` | Tagged: `{"__type__": "tuple", ...}` |
| `set` | `MapSet.t()` | Tagged: `{"__type__": "set", ...}` |
| `datetime` | `DateTime.t()` | Tagged: `{"__type__": "datetime", ...}` |
| `bytes` | `binary()` | Tagged: `{"__type__": "bytes", ...}` |
| `inf/-inf/nan` | `:infinity/:neg_infinity/:nan` | Tagged |

## Large Libraries

For large libraries like sympy (900+ items), consider:

```bash
# Generate specific submodules
mix snakebridge.gen sympy.solvers --module Sympy.Solvers

# Filter to needed functions only
mix snakebridge.gen sympy --functions solve,simplify,expand,factor
```

## Registry

SnakeBridge tracks all generated adapters in `priv/snakebridge/registry.json`:

```elixir
# Check what's generated
SnakeBridge.Registry.list_libraries()
# => ["json", "math", "numpy"]

SnakeBridge.Registry.get("json")
# => %{elixir_module: "Json", functions: 4, classes: 3, ...}

SnakeBridge.Registry.generated?("json")
# => true
```

## Direct Runtime API

For one-off calls without generating an adapter:

```elixir
alias SnakeBridge.Runtime

{:ok, result} = Runtime.call("math", "sqrt", [16])
# => {:ok, 4.0}

{:ok, data} = Runtime.call("json", "loads", [~s({"key": "value"})])
# => {:ok, %{"key" => "value"}}
```

## Configuration

```elixir
# config/config.exs
config :snakebridge,
  python_executable: "python3",
  auto_start_snakepit: true
```

## Testing

```bash
# Run unit tests (mocked, no Python required)
mix test

# Run with real Python integration
mix test --include real_python
```

## Architecture

1. **Introspection** (`priv/python/introspect.py`) - Analyzes Python libraries
2. **Type Mapping** (`lib/snakebridge/generator/type_mapper.ex`) - Python types → Elixir specs
3. **Source Generation** (`lib/snakebridge/generator/source_writer.ex`) - Generates .ex files
4. **Runtime** (`lib/snakebridge/runtime.ex`) - Executes Python via Snakepit
5. **Registry** (`lib/snakebridge/registry.ex`) - Tracks generated adapters

## License

MIT License - see [LICENSE](LICENSE) for details.
