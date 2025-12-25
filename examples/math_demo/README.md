# MathDemo - SnakeBridge Example

This example demonstrates SnakeBridge adapter generation and discovery-only APIs (no runtime Python calls).

## Quick Start

```bash
cd examples/math_demo
mix deps.get
mix compile
mix run -e Demo.run
```

That's it! The demo only inspects generated metadata and does not require Snakepit runtime setup.

## What Happens

1. `mix compile` runs the SnakeBridge compiler
2. SnakeBridge reads `config/config.exs`: `adapters: [:json, :math, :sympy]`
3. For each library:
   - Standard library (json, math) → uses system Python
   - Third-party (sympy) → uses `uv run --with sympy` to auto-install
4. Generates Elixir modules to `lib/snakebridge_generated/` with discovery metadata
5. Creates a `.gitignore` inside (auto-excluded from git)

## Generated Structure

```
lib/snakebridge_generated/
├── .gitignore          # Self-ignoring directory
├── json/json/
│   ├── _meta.ex        # Discovery functions
│   ├── json.ex         # Main module
│   └── classes/
├── math/math/
└── sympy/sympy/
```

Docs live in each adapter's `_meta.ex` and are exposed via `__functions__/0`, `__classes__/0`, and `__search__/1`.

## Interactive Usage

```bash
iex -S mix
```

```elixir
# Discovery
iex> Math.__functions__() |> length()
56

iex> Math.__search__("sqrt")
[{:sqrt, 1, Math, "Return the square root of x."}]

iex> Json.__classes__()
[...]

iex> MathDemo.generated_structure()
{:ok, %{root: ".../lib/snakebridge_generated", adapters: %{...}}}

iex> MathDemo.discover()
:ok

iex> Sympy.__functions__() |> length()
...

iex> Sympy.__search__("solve")
[...]
```

## Key Files

| File | Purpose |
|------|---------|
| `mix.exs` | Adds `:snakebridge` compiler |
| `config/config.exs` | Configures adapters |
| `lib/demo.ex` | Demo script |
| `lib/math_demo.ex` | Discovery helpers |

## Requirements

- Python 3.7+
- `uv` (recommended): `curl -LsSf https://astral.sh/uv/install.sh | sh`

If you don't want third-party adapters, remove `:sympy` from `config/config.exs`.
