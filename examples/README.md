# SnakeBridge Examples

This directory contains working examples demonstrating the current, manifest-first design.

## Setup

```bash
mix snakebridge.setup --venv .venv
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
export PYTHONPATH=$(pwd)/priv/python:$(pwd)/deps/snakepit/priv/python:$PYTHONPATH
```

## Run All Examples

```bash
./examples/run_all.sh
```

This runs the manifest-based examples for the three built-in libraries.

## Example List

### 1) SymPy Manifest Example (Real Python)

```bash
mix run --no-start examples/manifest_sympy.exs
```

Calls `simplify`, `solve`, and `free_symbols` via the built-in SymPy manifest.

### 2) PyLatexEnc Manifest Example (Real Python)

```bash
mix run --no-start examples/manifest_pylatexenc.exs
```

Calls `latex_to_text`, `parse`, and `unicode_to_latex` via the built-in pylatexenc manifest.

### 3) Math-Verify Manifest Example (Real Python)

```bash
mix run --no-start examples/manifest_math_verify.exs
```

Calls `parse`, `verify`, and `grade` via the built-in math-verify manifest.

## Notes

- Examples require real Python and will auto-start Snakepit (unless `auto_start_snakepit: false`).
- If you want to use a custom Python, export `SNAKEPIT_PYTHON` before running.
- Built-in manifests live in `priv/snakebridge/manifests`.
