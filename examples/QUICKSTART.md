# SnakeBridge Quick Start

## Run the Examples (Built-in Manifests)

### Step 1: Set up Python

```bash
mix snakebridge.setup --venv .venv
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
export PYTHONPATH=$(pwd)/priv/python:$(pwd)/priv/python/bridges:$(pwd)/deps/snakepit/priv/python:$PYTHONPATH
```

### Step 2: Run all examples

```bash
./examples/run_all.sh
```

This will run one example per built-in manifest:
- `sympy` (symbolic math)
- `pylatexenc` (LaTeX parsing)
- `math-verify` (answer equivalence)

---

## Common Problems

### "ModuleNotFoundError: No module named 'grpc'"

```bash
export SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3
.venv/bin/python3 -c "import grpc; print('OK')"
```

### "Snakepit is not running"

SnakeBridge auto-starts Snakepit by default. If you disabled auto-start, re-enable it or start Snakepit manually.

---

## Next Steps

- Full Python setup guide: `docs/PYTHON_SETUP.md`
- Examples overview: `examples/README.md`
- Manifest workflow: `README.md` (Manifest Workflow section)
