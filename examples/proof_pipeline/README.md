# ProofPipeline - SnakeBridge v3 Example

This example builds a multi-step proof grading pipeline using three Python libraries:

- **SymPy** for symbolic normalization
- **pylatexenc** for LaTeX handling
- **math_verify** for verification and grading

The demo defaults to a dry plan so it can run without Python libraries installed.

## Quick Start

```bash
cd examples/proof_pipeline
mix deps.get
mix compile
mix run -e Demo.run
```

To execute the live pipeline (requires Python libs installed and Snakepit runtime configured):

```bash
PROOF_PIPELINE_LIVE=1 mix run -e Demo.run
```

## What It Does

1. Parse LaTeX into nodes with pylatexenc
2. Convert and simplify with SymPy
3. Verify and grade with math_verify

## Generated Structure

```
lib/snakebridge_generated/
├── sympy.ex
├── pylatexenc.ex
└── math_verify.ex

.snakebridge/manifest.json
snakebridge.lock
```

## Interactive Usage

```bash
iex -S mix
```

```elixir
iex> ProofPipeline.sample_input()

iex> ProofPipeline.plan(ProofPipeline.sample_input())

iex> ProofPipeline.run(ProofPipeline.sample_input())
# requires Python runtime + libs
```

## Key Files

| File | Purpose |
|------|---------|
| `mix.exs` | Declares SnakeBridge libraries in deps |
| `lib/proof_pipeline.ex` | Pipeline logic |
| `lib/demo.ex` | Demo script |
| `lib/snakebridge_generated/*.ex` | Generated bindings |
| `.snakebridge/manifest.json` | Symbol manifest |
| `snakebridge.lock` | Runtime identity lock |
