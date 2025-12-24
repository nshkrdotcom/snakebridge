#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

python_examples=(
  "examples/manifest_sympy.exs"
  "examples/manifest_pylatexenc.exs"
  "examples/manifest_math_verify.exs"
)

if [[ -z "${SNAKEPIT_PYTHON:-}" && -x "$ROOT_DIR/.venv/bin/python3" ]]; then
  export SNAKEPIT_PYTHON="$ROOT_DIR/.venv/bin/python3"
fi

if [[ -z "${SNAKEPIT_PYTHON:-}" ]]; then
  echo "SNAKEPIT_PYTHON is not set and .venv/bin/python3 was not found." >&2
  echo "Run: mix snakebridge.setup --venv .venv" >&2
  exit 1
fi

export PYTHONPATH="$ROOT_DIR/priv/python:$ROOT_DIR/deps/snakepit/priv/python:${PYTHONPATH:-}"

for example in "${python_examples[@]}"; do
  echo "==> Running ${example}"
  mix run --no-start "$example"
  echo
done
