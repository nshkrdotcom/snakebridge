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
    {:snakebridge, "~> 0.4.0",
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
  strict: false,
  verbose: false,
  docs: [source: :python, cache_enabled: true]
```

### 4. Compile

```bash
mix compile
```

### 5. Use

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
└── numpy.ex
```

Metadata and environment identity are tracked alongside source:

```
.snakebridge/manifest.json
snakebridge.lock
```

## Configuration (Library Options)

```elixir
{:snakebridge, "~> 0.4.0",
 libraries: [
   numpy: [
     version: "~> 1.26",
     module_name: Np,
     python_name: "numpy",
     include: ["array", "zeros"],
     exclude: ["deprecated_fn"],
     streaming: ["predict"],
     submodules: true
   ],
   json: :stdlib
 ]}
```

## Runtime

SnakeBridge is compile-time only. Runtime behavior belongs to Snakepit.
The generated wrappers send payloads to Snakepit tools:

- `snakebridge.call`
- `snakebridge.stream`

Configure Snakepit separately under `config :snakepit`.

## Example Project

See `examples/math_demo` for a full v3 example with committed generated code.

```bash
cd examples/math_demo
mix deps.get
mix compile
```
