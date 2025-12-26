# Essential Enhancements for World-Class Status

Status: Analysis
Date: 2025-12-25

## Overview

This document distills the critique documents into a prioritized list of
essential enhancements. The critiques identified many desirable features; this
document focuses on what's **essential** for the current phase.

## Assessment Framework

Features are evaluated on:

1. **Pain Relief**: Does it solve a real, frequent problem?
2. **Differentiation**: Does it make SnakeBridge notably better than alternatives?
3. **Implementation Cost**: Can it be done with current architecture?
4. **Risk**: Does it introduce complexity that might backfire?

## P0: Essential (Block Release)

These features are required for a production-quality release.

### 1. Package Provisioning via UV

**Pain**: Developers must manually ensure Python packages are installed before
SnakeBridge can introspect. This is error-prone and undocumented.

**Solution**: Implement `Snakepit.PythonPackages` and `SnakeBridge.PythonEnv` as
proposed.

**Acceptance Criteria**:

- `mix snakebridge.setup` installs required packages
- `mix compile` in dev auto-installs if configured
- `mix compile` in CI fails cleanly if packages missing (strict mode)
- Packages recorded in `snakebridge.lock`

**Implementation Cost**: Medium (new Snakepit module, SnakeBridge orchestrator)

---

### 2. Strict Mode Enforcement

**Pain**: CI builds might accidentally trigger Python introspection, leading to
non-deterministic builds or failures when Python isn't available.

**Solution**: Implement proper strict mode:

```elixir
# In CI with strict: true
1. Load manifest.json
2. Scan project for library calls
3. If any symbol not in manifest → FAIL immediately
4. Never run Python introspection
```

**Acceptance Criteria**:

- `SNAKEBRIDGE_STRICT=1` or `config :snakebridge, strict: true`
- Clear error: "Symbol Math.foo/1 not in manifest. Run mix snakebridge.setup locally."
- No Python execution in strict mode

**Implementation Cost**: Low (modify compiler task logic)

---

### 3. Package Identity in Lockfile

**Pain**: Same `snakebridge.lock` on different machines with different package
versions produces different bindings. No reproducibility guarantee.

**Solution**: Extend lockfile:

```json
{
  "environment": {
    "python_packages_hash": "sha256:abc123..."
  },
  "python_packages": {
    "numpy": {"requested": "~=1.26", "resolved": "1.26.4", "hash": "sha256:..."},
    "sympy": {"requested": "~=1.12", "resolved": "1.12.1", "hash": "sha256:..."}
  }
}
```

**Acceptance Criteria**:

- Lockfile includes all Python packages with resolved versions
- Hash computed from resolved state (ideally from UV lockfile)
- Warning when lock and installed packages diverge

**Implementation Cost**: Medium (lockfile extension, package detection)

---

### 4. Introspection Error Classification

**Pain**: When introspection fails, SnakeBridge returns opaque errors. Developers
can't tell if the package is missing, incompatible, or if there's a bug.

**Solution**: Classify introspection errors:

```elixir
{:error, %SnakeBridge.IntrospectionError{
  type: :package_not_found,
  package: "numpy",
  suggestion: "Run: mix snakebridge.setup"
}}

{:error, %SnakeBridge.IntrospectionError{
  type: :import_error,
  package: "torch",
  python_error: "libcuda.so.1: cannot open shared object file",
  suggestion: "Install CUDA drivers or use torch-cpu"
}}
```

**Acceptance Criteria**:

- `ModuleNotFoundError` → `:package_not_found`
- `ImportError` → `:import_error` with details
- Script errors → `:introspection_bug`
- Timeout → `:timeout`

**Implementation Cost**: Low (parse Python stderr, structured error types)

---

## P1: High Value (Do Soon)

These features significantly improve the experience but don't block release.

### 5. PyPI Package Name Mapping

**Pain**: Some Python packages have different import names vs pip names
(e.g., `PIL` from `pillow`, `cv2` from `opencv-python`).

**Solution**: Add `pypi_package` option:

```elixir
libraries: [
  pillow: [
    version: "~=10.0",
    python_name: "PIL",        # import PIL
    pypi_package: "pillow"     # pip install pillow
  ]
]
```

**Implementation Cost**: Low (config extension, use in requirements derivation)

---

### 6. Structured Exception Translation

**Pain**: Python exceptions come back as text strings. Elixir code can't pattern
match on exception types.

**Solution**: The Snakepit runtime already has `Snakepit.Error`. Extend it:

```elixir
%Snakepit.Error{
  category: :python_error,
  exception_type: "ValueError",
  message: "shapes (3,4) and (2,2) not aligned",
  context: %{shape_a: [3, 4], shape_b: [2, 2]},
  python_traceback: "..."
}
```

**Acceptance Criteria**:

- Common Python exceptions have dedicated Elixir representations
- Errors include context where available (shapes, types, etc.)
- Pattern matching on `exception_type` works

**Implementation Cost**: Medium (Snakepit Python bridge modification)

---

### 7. Error Message Excellence

**Pain**: Errors tell you what went wrong but not how to fix it.

**Solution**: Every error includes actionable guidance:

```
** (SnakeBridge.TensorShapeError) Shape mismatch in Torch.matmul/2

  Expected: tensor A columns (128) to match tensor B rows (256)
  Got: A.shape = (32, 128), B.shape = (256, 64)

  Common causes:
    - Forgot to transpose: try Torch.transpose(b, 0, 1)
    - Batch dimension mismatch: check batch sizes

  Call site: lib/my_app/model.ex:45
```

**Implementation Cost**: Medium (error formatting, common pattern database)

---

### 8. RST/Math Documentation Rendering

**Pain**: SymPy, NumPy, and other scientific libraries use reStructuredText with
LaTeX math. Current doc rendering is poor.

**Solution**:

1. Parse RST to HTML via Python's docutils
2. Convert LaTeX to HTML via KaTeX (JS) or Python renderer
3. Cache rendered docs

**Acceptance Criteria**:

- Math formulas render correctly in IEx and ExDoc
- Code blocks preserve syntax
- References resolve within library

**Implementation Cost**: High (RST parser integration, math rendering pipeline)

---

## P2: Differentiators (Future)

These features would make SnakeBridge exceptional but are not essential now.

### 9. Zero-Copy Tensor Protocol

**Value**: Eliminates serialization overhead for large arrays. 10GB tensor
passes between Elixir and Python without copying.

**Approach**:

- Apache Arrow C Data Interface for CPU tensors
- DLPack for GPU tensors
- Shared memory (mmap) for inter-process transfer

**Dependency**: Requires Nx integration and significant Snakepit changes.

**Timeline**: Post-1.0

---

### 10. Livebook Integration

**Value**: ML practitioners live in notebooks. Deep Livebook integration makes
SnakeBridge the "better Jupyter."

**Features**:

- Python cells in Livebook
- Automatic variable sharing (Elixir ↔ Python)
- Inline matplotlib/plotly rendering
- GPU memory dashboard

**Timeline**: Post-1.0

---

### 11. Hardware Abstraction Layer

**Value**: Automatic CUDA/MPS/CPU detection and fallback.

**Features**:

```elixir
torch: [
  hardware: [prefer: [:cuda, :mps, :cpu], fallback: :graceful]
]
```

**Timeline**: Post-1.0

---

### 12. Observability (OpenTelemetry)

**Value**: Production visibility into cross-language calls.

**Features**:

- Spans for: adapter generation, Python calls, queue time, serialization
- Tensor-aware telemetry (shapes, memory, device)
- LiveDashboard integration

**Dependency**: Snakepit already has telemetry infrastructure.

**Timeline**: 1.x (incremental)

---

## Immediate Action Items

Based on this analysis, the immediate work is:

1. **Implement `Snakepit.PythonPackages`** (P0-1)
2. **Implement strict mode enforcement** (P0-2)
3. **Extend lockfile with package identity** (P0-3)
4. **Add introspection error classification** (P0-4)
5. **Add pypi_package config option** (P1-5)

Items 1-4 are blockers. Item 5 is needed for any non-trivial library.

## What We're Explicitly Deferring

- Zero-copy tensors (complex, post-1.0)
- Livebook integration (separate project)
- Hardware abstraction (post-1.0)
- Full RST rendering (can ship with basic markdown conversion)
- Gradient-aware boundary crossing (very complex)
- Ecosystem integrations (wandb, HF Hub) (post-1.0)

## Conclusion

The v0.4.0 architecture is sound. The essential work is:

1. Package provisioning (closes the Snakepit integration loop)
2. Strict mode (enables CI safety)
3. Better errors (developer experience)

These are achievable without architectural changes. The "world-class" features
(zero-copy, observability) can come later without breaking the current design.
