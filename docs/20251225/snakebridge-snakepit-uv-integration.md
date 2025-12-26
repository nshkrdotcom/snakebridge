# SnakeBridge + Snakepit UV Integration Design

Status: design

## Summary

SnakeBridge is compile-time only. It scans Elixir code, introspects Python, and
emits deterministic bindings. Snakepit is the runtime substrate and already owns
hermetic Python (uv-managed) and runtime identity. The missing piece is a
compile-time integration that ensures the Snakepit-managed Python environment
also has the required Python packages before SnakeBridge introspects.

This document defines an "ultimate" integration where SnakeBridge delegates all
Python provisioning to Snakepit without touching system packages, while keeping
SnakeBridge compile-time only and deterministic.

## Goals

- Use Snakepit's uv-managed Python runtime for SnakeBridge introspection.
- Ensure required Python packages are installed in the managed environment.
- Never install into system Python or user site-packages.
- Keep SnakeBridge deterministic (no timestamps, reproducible lockfiles).
- Provide clear UX for dev/CI: auto-install in dev, strict failure in CI.
- Record Python runtime and package identity in `snakebridge.lock`.

## Non-goals

- SnakeBridge does not execute Python at runtime (Snakepit does).
- No mid-compile injection or runtime code generation.
- No dependency resolution beyond pip/uv package install.

## Existing Building Blocks

- `Snakepit.PythonRuntime`: resolves managed/system Python and records runtime
  identity (`python_version`, `python_platform`, `python_runtime_hash`).
- `SnakeBridge.PythonRunner.System`: executes Python using the runtime resolved
  by Snakepit.
- `Snakepit.Bootstrap`: dev/CI setup using `priv/python/requirements.txt` and
  `.venv` (pip-based), not uv-managed packages.

The integration should not require `Snakepit.Bootstrap` for compile-time
introspection; it should be a targeted provisioning step.

## Proposed Architecture

### New Component: Snakepit.PythonPackages

A Snakepit-owned package installer with a single responsibility:

- Ensure a given requirements spec is installed into the runtime Python.
- Use uv when the runtime is managed (`strategy: :uv`).
- Fall back to pip when the runtime is `:system` or explicitly configured.

Suggested API:

```elixir
Snakepit.PythonPackages.ensure!(requirements, opts)
Snakepit.PythonPackages.installed?(requirements, opts)
Snakepit.PythonPackages.lock_metadata(requirements, opts)
```

Where `requirements` can be:

- `{:file, path}` (a requirements.txt file)
- `{:list, ["sympy~=1.12", "pylatexenc~=2.10"]}`
- `:libraries` (derive from SnakeBridge libraries)

### New Component: SnakeBridge.PythonEnv

A compile-time orchestrator used by the SnakeBridge compiler:

```elixir
SnakeBridge.PythonEnv.ensure!(config)
```

Responsibilities:

- Determine whether auto-install is enabled.
- Build the requirements spec from `libraries:` in `mix.exs`.
- Delegate to `Snakepit.PythonRuntime.install_managed/2` and
  `Snakepit.PythonPackages.ensure!/2`.
- Emit deterministic package metadata for `snakebridge.lock`.

### Compile-time Flow

1. Load SnakeBridge config.
2. If `python_env.auto_install` is enabled:
   - Ensure managed Python is installed via `Snakepit.PythonRuntime`.
   - Ensure packages are installed via `Snakepit.PythonPackages`.
3. Run introspection using `SnakeBridge.PythonRunner` (already uses Snakepit
   runtime resolution).
4. Generate bindings and update manifest + lock.

### Runtime Flow

No changes to SnakeBridge runtime behavior. Generated wrappers call Snakepit
(`snakebridge.call` / `snakebridge.stream`). Snakepit uses the same runtime and
installed packages.

## Requirements Spec and Package Mapping

SnakeBridge libraries are declared in `mix.exs` and converted into Python
requirements:

```elixir
libraries: [
  sympy: "~> 1.12",
  pylatexenc: "~> 2.10",
  math_verify: "~> 0.1"
]
```

Normalized requirements:

- `sympy~=1.12`
- `pylatexenc~=2.10`
- `math-verify~=0.1` (note PyPI name)

Add per-library overrides:

```elixir
math_verify: [
  version: "~> 0.1",
  pypi_package: "math-verify",
  extras: ["antlr"]
]
```

Stdlib libraries (`:stdlib`) are excluded from requirements.

## Package Installation Strategy

- Managed runtime: use uv with explicit interpreter:
  - `uv pip install --python <path> -r requirements.txt`
- System runtime: use interpreter pip:
  - `<python> -m pip install -r requirements.txt`

Always set environment flags to prevent system contamination:

- `PYTHONNOUSERSITE=1`
- `PIP_DISABLE_PIP_VERSION_CHECK=1`
- `PIP_NO_INPUT=1`

### Optional "Backup" Strategy

For safer upgrades, allow staged installs:

- Install into a new venv directory `priv/snakepit/python/venv.new`.
- On success, swap to `venv` and keep `venv.prev` for rollback.
- If install fails, keep the previous environment intact.

This step is optional but recommended for CI reliability.

## Lockfile Integration

Extend `snakebridge.lock` to include package identity:

```json
{
  "environment": {
    "python_runtime_hash": "...",
    "python_version": "...",
    "python_platform": "...",
    "python_packages_hash": "sha256:..."
  },
  "python_packages": [
    "sympy~=1.12",
    "pylatexenc~=2.10",
    "math-verify~=0.1"
  ]
}
```

The package hash is computed from the normalized, sorted requirements list.
If the hash changes, bindings are invalidated and regenerated.

## Configuration

### SnakeBridge

```elixir
config :snakebridge, :python_env,
  auto_install: :dev,          # :never | :dev | :always
  requirements: :libraries,    # :libraries | {:file, path} | {:list, reqs}
  fail_on_missing: true
```

### Snakepit

```elixir
config :snakepit, :python,
  strategy: :uv,
  managed: true,
  python_version: "3.11.8",
  runtime_dir: "priv/snakepit/python",
  cache_dir: "priv/snakepit/python/cache",
  extra_env: %{"PYTHONNOUSERSITE" => "1"}

config :snakepit, :python_packages,
  installer: :uv,
  env_dir: "priv/snakepit/python/venv"
```

## UX and Failure Modes

- In dev: auto-install by default, clear logs.
- In CI/strict mode: do not auto-install; fail with guidance:
  - "Run mix snakebridge.setup or mix snakepit.setup"
- Missing uv or managed runtime -> fail fast with clear instructions.

## New Mix Tasks

- `mix snakebridge.setup`:
  - Calls `SnakeBridge.PythonEnv.ensure!/1` only.
  - No codegen, safe for preflight.

`mix snakepit.setup` remains the full runtime bootstrap (grpc, dev venv, etc.).

## Testing Plan

- Unit tests:
  - Requirement normalization and package mapping.
  - Lock hash stability.
  - Auto-install gating by config/env.
- Integration tests:
  - Managed uv runtime path is used for introspection.
  - Missing packages fail in strict mode with guidance.

## Migration Plan

1. Add Snakepit uv-managed config.
2. Add `:python_env` config to SnakeBridge.
3. Run `mix snakebridge.setup` to provision runtime.
4. Commit updated `snakebridge.lock` and generated bindings.

## Open Questions

- Should staged installs be default or opt-in?
- Should package installs be shared across apps or per-project only?
- How should we detect package presence quickly without running imports?

