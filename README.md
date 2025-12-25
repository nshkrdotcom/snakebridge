# SnakeBridge

[![Elixir](https://img.shields.io/badge/elixir-1.14+-purple.svg)](https://elixir-lang.org)
[![Hex.pm](https://img.shields.io/hexpm/v/snakebridge.svg)](https://hex.pm/packages/snakebridge)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Generate type-safe Elixir adapters for Python libraries with full IDE support.

Built on [Snakepit](https://hex.pm/packages/snakepit) for Python runtime management.

## Quick Start

### 1. Add Dependency

```elixir
# mix.exs
def deps do
  [
    {:snakebridge, "~> 0.4"}
  ]
end
```

### 2. Add Compiler

```elixir
# mix.exs
def project do
  [
    compilers: [:snakebridge] ++ Mix.compilers(),
    # ...
  ]
end
```

### 3. Configure Adapters

```elixir
# config/config.exs
config :snakebridge,
  adapters: [:json, :math, :sympy]
```

### 4. Compile

```bash
$ mix compile
SnakeBridge: Generating json adapter...
  Generated 4 functions, 3 classes
SnakeBridge: Generating math adapter...
  Generated 56 functions, 0 classes
SnakeBridge: Generating sympy adapter...
  Generated 481 functions, 392 classes
```

### 5. Use

```elixir
iex> Math.sqrt(2)
{:ok, 1.4142135623730951}

iex> Json.dumps(%{"hello" => "world"}, false, true, true, true, nil, nil, nil, nil, false, %{})
{:ok, "{\"hello\": \"world\"}"}

iex> Math.__functions__() |> Enum.take(3)
[
  {:acos, 1, Math, "Return the arc cosine..."},
  {:acosh, 1, Math, "Return the inverse hyperbolic cosine..."},
  {:asin, 1, Math, "Return the arc sine..."}
]
```

## How It Works

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Python Module  │────>│   mix compile    │────>│  Elixir Adapter │
│  (e.g., json)   │     │  :snakebridge    │     │  (Json module)  │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                              │
                    Introspects Python:
                    - Function signatures
                    - Type annotations
                    - Docstrings
                    - Classes
```

1. **Compile-time generation**: The `:snakebridge` compiler runs before Elixir compilation
2. **Python introspection**: Each configured library is introspected for functions, classes, and types
3. **Elixir code generation**: Type-safe modules with `@doc`, `@spec`, and discovery functions
4. **Auto-gitignore**: Generated code goes to `lib/snakebridge_generated/` with a self-contained `.gitignore`

Your repo stays clean - generated code is excluded from git but visible to your IDE.

## Generated Structure

```
lib/snakebridge_generated/
├── .gitignore              # Contains "* !.gitignore" (self-ignoring)
├── json/
│   └── json/
│       ├── _meta.ex        # Discovery functions
│       ├── json.ex         # Main module
│       └── classes/
│           ├── json_encoder.ex
│           └── json_decoder.ex
├── math/
│   └── math/
│       ├── _meta.ex
│       └── math.ex
└── sympy/
    └── sympy/
        ├── _meta.ex
        ├── sympy.ex
        └── classes/
            └── ... (392 class modules)
```

## Discovery Functions

Every generated module includes:

```elixir
# List all functions with arities and documentation
Json.__functions__()
# => [{:dump, 12, Json, "Serialize obj..."}, {:dumps, 11, Json, "..."}, ...]

# List all classes
Json.__classes__()
# => [{:JSONEncoder, Json.JSONEncoder, "Extensible JSON encoder..."}, ...]

# Search functions by name or documentation
Json.__search__("decode")
# => [{:loads, 8, Json, "Deserialize s to a Python object..."}, ...]

# Standard IEx help works
iex> h Json.dumps
```

## Configuration Options

```elixir
config :snakebridge,
  adapters: [
    # Simple - just the library name
    :json,
    :math,

    # With options
    {:numpy, functions: ["array", "zeros", "ones"]},
    {:sympy, exclude: ["init_printing"]}
  ]
```

## Type System

SnakeBridge handles the impedance mismatch between Python and Elixir types:

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

## Manual Generation

For cases where you want to commit generated code:

```bash
# Generate an adapter manually
mix snakebridge.gen numpy

# Options
mix snakebridge.gen numpy --functions array,zeros,ones
mix snakebridge.gen os --exclude system,exec
mix snakebridge.gen requests --output lib/my_app/http/
mix snakebridge.gen json --force  # Regenerate existing

# Management
mix snakebridge.list   # List generated adapters
mix snakebridge.info json  # Show adapter details
mix snakebridge.clean json  # Remove an adapter
```

## Example Project

See `examples/math_demo/` for a complete working example:

```bash
cd examples/math_demo
mix deps.get
mix compile           # Generates adapters automatically
mix run -e Demo.run   # Run the demo
```

## Requirements

- Elixir 1.14+
- Python 3.7+
- **Recommended**: [`uv`](https://github.com/astral-sh/uv) for automatic Python package management

### Automatic Dependency Management

If you have `uv` installed, SnakeBridge automatically installs Python packages in temporary environments during generation:

```bash
# Install uv (one-time setup)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Now just use SnakeBridge - no pip install needed!
mix compile
# => SnakeBridge: Generating sympy adapter...
#    (uv automatically installs sympy in temp environment)
```

Without `uv`, you'll need to install packages manually: `pip install numpy sympy`

## Direct Runtime API

For one-off calls without generating an adapter:

```elixir
{:ok, result} = SnakeBridge.call("math", "sqrt", %{x: 16})
# => {:ok, 4.0}

{:ok, data} = SnakeBridge.call("json", "loads", %{s: ~s({"key": "value"})})
# => {:ok, %{"key" => "value"}}
```

## Testing

```bash
# Run unit tests (mocked, no Python required)
mix test

# Run with real Python integration
mix test --include real_python
```

## License

MIT License - see [LICENSE](LICENSE) for details.
