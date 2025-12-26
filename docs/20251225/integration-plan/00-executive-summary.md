# SnakeBridge + Snakepit Integration: Executive Summary

Status: Analysis & Planning
Date: 2025-12-25

## Situation

SnakeBridge v0.4.0 is a complete rewrite implementing a compile-time pre-pass
model (Scan → Introspect → Generate). It delegates all runtime execution to
Snakepit. The proposed UV integration design aims to close the loop by having
Snakepit provision Python packages before SnakeBridge introspects.

## Key Findings

### What Works

1. **Compile-time Pipeline**: The Scan → Introspect → Generate pipeline is
   sound and implemented.

2. **Snakepit UV Runtime**: `Snakepit.PythonRuntime` already supports UV-managed
   Python interpreters with `strategy: :uv, managed: true`.

3. **Runtime Identity**: Snakepit tracks Python version, platform, and runtime
   hash via `runtime_identity/0`.

4. **Deterministic Generation**: Generated source files are stable (no
   timestamps in output), manifest is sorted alphabetically.

### Critical Gaps

1. **Package Management Missing**: Snakepit has UV for Python interpreter but no
   `Snakepit.PythonPackages` module for pip/uv package installation. The
   proposed design addresses this but it doesn't exist.

2. **Bootstrap Mismatch**: `Snakepit.Bootstrap` uses pip-based venv with
   `requirements.txt`, not UV for packages. This conflicts with the hermetic
   vision.

3. **Lockfile Incomplete**: `snakebridge.lock` tracks Python runtime identity
   but not package versions/hashes as proposed.

4. **No Auto-Install**: The proposed `python_env.auto_install` mechanism doesn't
   exist. Developers must manually ensure packages are installed.

5. **Strict Mode Undefined**: While `:strict` config exists in SnakeBridge, the
   proposed CI-safe "fail if generation needed" behavior is not fully
   implemented.

### Architecture Disconnects

| Component | SnakeBridge Assumes | Snakepit Provides | Gap |
|-----------|---------------------|-------------------|-----|
| Package Install | `Snakepit.PythonPackages.ensure!/2` | Nothing | Full implementation needed |
| Python Resolve | `Snakepit.PythonRuntime.resolve_executable/0` | Yes | None |
| Runtime Identity | `Snakepit.PythonRuntime.runtime_identity/0` | Yes | Need package hash |
| Runtime Env | `Snakepit.PythonRuntime.runtime_env/0` | Yes | None |
| Package Mapping | Library config → requirements | Not present | Needs library → pypi mapping |

## Essential Enhancements (Priority Order)

From the critique documents, these are essential for "world-class" status:

### P0 - Must Have

1. **Package Provisioning** (UV Integration)
   - Implement `Snakepit.PythonPackages` module
   - Auto-install in dev, strict failure in CI
   - Package identity in lockfile

2. **Strict Mode Enforcement**
   - CI should fail if generation would occur
   - Clear workflow: dev generates → commit → CI verifies

3. **Determinism Guarantees**
   - Package hashes in lockfile
   - Full environment identity (Python + packages + platform)

### P1 - High Value

4. **Structured Exception Translation**
   - Python exceptions → pattern-matchable Elixir structs
   - Context preservation (shapes, dtypes for ML errors)

5. **Error Message Excellence**
   - Errors that teach, not just report
   - Include fix suggestions

6. **RST/Math Rendering**
   - Proper docstring rendering for SymPy-class libraries
   - KaTeX for math notation

### P2 - Differentiators (Future)

7. **Zero-Copy Tensor Protocol**
   - Apache Arrow / DLPack integration
   - Shared memory for large arrays

8. **Observability**
   - OpenTelemetry spans for generation and calls
   - Tensor-aware telemetry (shapes, memory)

## Recommended Path

1. **Implement `Snakepit.PythonPackages`** as proposed, but with clearer API
2. **Add `SnakeBridge.PythonEnv`** as thin orchestrator
3. **Extend `snakebridge.lock`** to include package identity
4. **Implement strict mode** properly for CI safety
5. **Add library → pypi package mapping** for non-obvious names

## Document Index

- `01-gap-analysis.md` - Detailed gap analysis between codebases
- `02-uv-integration-critique.md` - Critical review of proposed UV design
- `03-essential-enhancements.md` - Must-have features from wishlist
- `04-implementation-plan.md` - Concrete implementation steps
- `05-determinism-strategy.md` - Deep dive on determinism
- `06-runtime-integration.md` - Runtime integration patterns
