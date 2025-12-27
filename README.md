<p align="center">
  <img src="assets/snakebridge.svg" alt="SnakeBridge Logo">
</p>

# SnakeBridge

[![Elixir](https://img.shields.io/badge/elixir-1.14+-purple.svg)](https://elixir-lang.org)
[![Hex.pm](https://img.shields.io/hexpm/v/snakebridge.svg)](https://hex.pm/packages/snakebridge)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

SnakeBridge generates type-safe Elixir bindings for Python libraries at **compile time**.
Runtime execution is handled by [Snakepit](https://hex.pm/packages/snakepit).

## Quick Start

### 1. Add Dependency (with libraries)

```elixir
# mix.exs
defp deps do
  [
    {:snakebridge, "~> 0.5.0",
     libraries: [
       json: :stdlib,
       math: :stdlib,
       numpy: "~> 1.26"
     ]}
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

### 3. Optional Configuration

```elixir
# config/config.exs
config :snakebridge,
  generated_dir: "lib/snakebridge_generated",
  metadata_dir: ".snakebridge",
  auto_install: :dev,
  strict: false,
  verbose: false,
  docs: [source: :python, cache_enabled: true]
```

`auto_install` supports `:never | :dev | :always` (default: `:dev`).

### 4. Provision Python Packages (optional)

```bash
mix snakebridge.setup
```

### 5. Compile

```bash
mix compile
```

### 6. Use

```elixir
iex> Math.sqrt(2)
{:ok, 1.4142135623730951}

iex> Json.dumps(%{"hello" => "world"})
{:ok, "{\"hello\": \"world\"}"}

iex> Math.__functions__() |> Enum.take(3)
[
  {:acos, 1, Math, "Return the arc cosine..."},
  {:acosh, 1, Math, "Return the inverse hyperbolic cosine..."},
  {:asin, 1, Math, "Return the arc sine..."}
]
```

## How It Works

SnakeBridge is a **pre-pass generator**:

1. Scan the project for library calls.
2. Introspect Python using the Snakepit-configured runtime.
3. Generate Elixir modules under `lib/snakebridge_generated/*.ex`.

Generated source is **committed to git**. There are no timestamps and no auto-gitignore.

## Generated Layout

```
lib/snakebridge_generated/
├── json.ex
├── math.ex
├── numpy.ex
└── helpers/
    └── sympy.ex
```

Metadata and environment identity are tracked alongside source:

```
.snakebridge/manifest.json
snakebridge.lock
```

## Configuration (Library Options)

```elixir
{:snakebridge, "~> 0.5.0",
 libraries: [
   numpy: [
     version: "~> 1.26",
     module_name: Np,
     python_name: "numpy",
     pypi_package: "numpy",
     extras: ["cuda"],
     include: ["array", "zeros"],
     exclude: ["deprecated_fn"],
     streaming: ["predict"],
     submodules: true
   ],
   json: :stdlib
]}
```

## Strict Mode (CI)

Strict mode prevents introspection and fails if generation would be required.

```bash
SNAKEBRIDGE_STRICT=1 mix compile
```

When strict mode fails, run `mix snakebridge.setup`, then `mix compile`,
commit the updated manifest and generated files, and retry CI.

## Runtime

SnakeBridge is compile-time only. Runtime behavior belongs to Snakepit.
The generated wrappers send payloads to Snakepit tools:

- `snakebridge.call`
- `snakebridge.stream`

## Helpers

Helpers are opt-in Python functions registered explicitly in helper modules.
They are discovered at compile time and wrapped under `lib/snakebridge_generated/helpers/`.

```python
# priv/python/helpers/sympy_helpers.py
def parse_implicit(expr):
    # custom logic here
    return expr

__snakebridge_helpers__ = {
    "sympy.parse_implicit": parse_implicit
}
```

```elixir
# config/config.exs
config :snakebridge,
  helper_paths: ["priv/python/helpers"],
  helper_pack_enabled: true,
  helper_allowlist: :all,
  inline_enabled: false
```

```elixir
iex> Sympy.Helpers.parse_implicit("2x")
{:ok, "2x"}
```

Configure Snakepit separately under `config :snakepit`.

## Example Project

See `examples/math_demo` for a full v3 example with committed generated code.

```bash
cd examples/math_demo
mix deps.get
mix compile
```
