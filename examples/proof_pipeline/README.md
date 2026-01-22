# ProofPipeline - SnakeBridge v3 Example

This example builds a multi-step proof grading pipeline using three Python libraries:

- **SymPy** for symbolic normalization
- **pylatexenc** for LaTeX handling
- **math_verify** for verification

The demo runs the live pipeline and requires Python libraries installed.

## Quick Start

```bash
cd examples/proof_pipeline
mix deps.get
mix compile
mix run --no-start -e Demo.run
```

The first compile auto-installs the Python runtime and packages (managed via uv).
This demo wraps execution in `SnakeBridge.script do ... end` so Python workers
are cleaned up when the script exits. Defaults are `exit_mode: :auto` and
`stop_mode: :if_started`; use `SnakeBridge.script(opts) do ... end` for custom
lifecycle options.

## What It Does

1. Parse LaTeX into nodes with pylatexenc
2. Convert and simplify with SymPy
3. Verify with math_verify

## Generated Structure

```
lib/snakebridge_generated/
├── math_verify/
│   └── __init__.ex
├── pylatexenc/
│   └── __init__.ex
└── sympy/
    └── __init__.ex

.snakebridge/manifest.json
snakebridge.lock
```

## Interactive Usage

```bash
iex -S mix
```

```elixir
iex> ProofPipeline.sample_input()

iex> ProofPipeline.run(ProofPipeline.sample_input())
# requires Python runtime + libs
```

## Key Files

| File | Purpose |
|------|---------|
| `mix.exs` | Declares Python libraries via `python_deps` |
| `lib/proof_pipeline.ex` | Pipeline logic |
| `lib/demo.ex` | Demo script |
| `lib/snakebridge_generated/**/*.ex` | Generated bindings |
| `.snakebridge/manifest.json` | Symbol manifest |
| `snakebridge.lock` | Runtime identity lock |
