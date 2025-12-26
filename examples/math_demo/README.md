# MathDemo - SnakeBridge v3 Example

This example demonstrates SnakeBridge v3 compile-time generation and discovery APIs.
Runtime calls are intentionally omitted.

## Quick Start

```bash
cd examples/math_demo
mix deps.get
mix compile
mix run -e Demo.run
```

## What Happens

1. `mix compile` runs the SnakeBridge pre-pass.
2. Libraries are read from `mix.exs` dependency options.
3. SnakeBridge scans, introspects, and generates modules under `lib/snakebridge_generated/`.
4. Generated source, manifest, and lock are committed to git.

## Generated Structure

```
lib/snakebridge_generated/
├── json.ex
└── math.ex

.snakebridge/manifest.json
snakebridge.lock
```

## Interactive Usage

```bash
iex -S mix
```

```elixir
# Discovery
iex> Math.__functions__() |> length()
3

iex> Math.__search__("sq")
[%{name: :sqrt, summary: "Return the square root.", relevance: 0.9}]

iex> Json.__classes__()
[...]

iex> MathDemo.generated_structure()
{:ok, %{root: ".../lib/snakebridge_generated", libraries: ["json", "math"]}}

iex> MathDemo.discover()
:ok
```

## Key Files

| File | Purpose |
|------|---------|
| `mix.exs` | Declares SnakeBridge libraries in deps |
| `config/config.exs` | Compile-time options only |
| `lib/snakebridge_generated/*.ex` | Generated bindings (committed) |
| `.snakebridge/manifest.json` | Symbol manifest (committed) |
| `snakebridge.lock` | Runtime identity lock (committed) |
| `lib/demo.ex` | Demo script |
| `lib/math_demo.ex` | Discovery helpers |

## Requirements

- Python 3.7+
- Snakepit configured for runtime execution when you call generated functions
