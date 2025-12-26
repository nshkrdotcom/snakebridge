# Critique: UV Integration Design

Status: Analysis
Date: 2025-12-25

## Overview

This document critically reviews the proposed "SnakeBridge + Snakepit UV
Integration Design" from the user's context. The design is sound in principle
but has several areas that need refinement.

## Design Summary

The proposal introduces:

1. `Snakepit.PythonPackages` - Package installer using uv/pip
2. `SnakeBridge.PythonEnv` - Compile-time orchestrator
3. Extended `snakebridge.lock` - Package identity tracking
4. Auto-install mechanism - Dev vs CI behavior

## What's Good

### 1. Clear Ownership Boundary

> "SnakeBridge is compile-time only... Snakepit is the runtime substrate."

This is correct. SnakeBridge should not manage Python environments; it should
use whatever Snakepit provides. The design respects this boundary.

### 2. UV-First Strategy

Using UV for package installation is the right choice:

- 10-100x faster than pip
- Reproducible resolution
- Proper lockfile support
- Cross-platform wheel selection

### 3. Library → Requirements Mapping

```elixir
libraries: [
  sympy: "~> 1.12",
  pylatexenc: "~> 2.10",
  math_verify: [version: "~> 0.1", pypi_package: "math-verify", extras: ["antlr"]]
]
```

This is essential. Many Python packages have different import names vs PyPI
names. The per-library override mechanism is flexible.

### 4. Package Identity in Lock

```json
{
  "python_packages_hash": "sha256:...",
  "python_packages": ["sympy~=1.12", ...]
}
```

Computing a hash from sorted requirements enables:

- Detecting when packages change
- Invalidating bindings on package upgrade
- Reproducibility verification

## Issues and Improvements

### Issue 1: Requirements Derivation from Libraries

The design proposes:

```elixir
requirements: :libraries  # derive from SnakeBridge libraries
```

**Problem**: This tightly couples Snakepit to SnakeBridge semantics. Snakepit
shouldn't need to know about SnakeBridge's library format.

**Better**: SnakeBridge should derive the requirements list and pass it to
Snakepit:

```elixir
# In SnakeBridge.PythonEnv
requirements = derive_requirements(config.libraries)
Snakepit.PythonPackages.ensure!({:list, requirements}, opts)
```

This keeps Snakepit generic. It just installs packages; it doesn't parse
SnakeBridge configs.

---

### Issue 2: Version Constraint Translation

The design shows Elixir-style version constraints:

```elixir
sympy: "~> 1.12"
```

Becoming Python/PEP-440 constraints:

```
sympy~=1.12
```

**Problem**: The translation isn't trivial:

| Elixir | PEP-440 | Notes |
|--------|---------|-------|
| `~> 1.12` | `~=1.12` | Compatible release |
| `~> 1.12.0` | `~=1.12.0` | Patch-compatible |
| `>= 1.0 and < 2.0` | `>=1.0,<2.0` | Range |
| `:stdlib` | (omit) | No pip install |
| `"1.12"` | `==1.12` | Exact? or prefix? |

**Recommendation**: Document the translation rules explicitly. Consider using
PEP-440 strings directly in library config to avoid ambiguity:

```elixir
sympy: [version: "~=1.12"]  # PEP-440 directly
```

---

### Issue 3: Auto-Install Granularity

The design proposes:

```elixir
auto_install: :dev | :never | :always
```

**Problem**: This is a global setting. In practice, you might want:

- Some packages always installed (numpy, scipy)
- Some packages optional (torch-cuda only on GPU machines)
- Some packages dev-only (pytest, black)

**Better**: Per-library install policy:

```elixir
libraries: [
  numpy: [version: "~=1.26", install: :always],
  torch: [version: "~=2.0", install: :optional],
  pytest: [version: "~=7.0", install: :dev]
]
```

With defaults based on global `auto_install` setting.

---

### Issue 4: Installer Selection Logic

The design proposes:

```
Managed runtime → use uv
System runtime → use pip
```

**Problem**: This conflates runtime strategy with package installer. You might
want:

- UV-managed runtime + pip packages (for compatibility)
- System runtime + uv packages (for speed)

**Better**: Separate configuration:

```elixir
config :snakepit, :python,
  strategy: :uv,          # runtime management
  managed: true

config :snakepit, :python_packages,
  installer: :uv,         # package installation (independent)
  env_dir: "..."
```

The current design does have `installer: :uv` in config, but the logic
description conflates them.

---

### Issue 5: Staged Install Complexity

The design proposes:

> "For safer upgrades, allow staged installs: Install into venv.new, on success
> swap to venv, keep venv.prev for rollback."

**Problem**: This adds significant complexity:

- Directory management
- Symlink or atomic rename semantics
- Cleanup of old versions
- Recovery from partial failures

**Assessment**: This is a "nice to have" for CI reliability but not MVP. The
design correctly marks it as optional. Recommend deferring to post-v1.

For MVP, a simple "install to venv, fail atomically" is sufficient.

---

### Issue 6: Lockfile Hash Stability

The design proposes:

> "The package hash is computed from the normalized, sorted requirements list."

**Problem**: This hash doesn't account for:

1. **Resolved versions**: `numpy~=1.26` might resolve to 1.26.0 or 1.26.4
2. **Platform-specific wheels**: Different hashes on Linux vs macOS
3. **Transitive dependencies**: numpy 1.26.0 might pull different deps

**Better**: Use UV's lockfile (`uv.lock`) as the source of truth:

```elixir
# After installation
{:ok, lock_content} = File.read("uv.lock")
lock_hash = :crypto.hash(:sha256, lock_content) |> Base.encode16()
```

This captures the full resolved dependency graph, not just the requirements.

---

### Issue 7: Package Presence Detection

The design asks:

> "How should we detect package presence quickly without running imports?"

**Answer**: Use `uv pip show` or `importlib.metadata`:

```bash
# Fast (uv native)
uv pip show numpy --python /path/to/python

# Fallback (Python stdlib)
python -c "import importlib.metadata; print(importlib.metadata.version('numpy'))"
```

For bulk detection:

```bash
uv pip freeze --python /path/to/python | grep -E "^(numpy|scipy|sympy)=="
```

**Implementation**: Cache the freeze output at install time, invalidate on any
install operation.

---

### Issue 8: CI Failure Guidance

The design proposes:

> "In CI/strict mode: do not auto-install; fail with guidance: 'Run mix
> snakebridge.setup or mix snakepit.setup'"

**Problem**: These are two different commands with different scopes:

- `mix snakepit.setup` - Full Snakepit bootstrap (gRPC, venv, etc.)
- `mix snakebridge.setup` - Just package provisioning for introspection

**Clarification Needed**: Which is authoritative? If both exist, when to use
which?

**Recommendation**: Single command with options:

```bash
mix snakebridge.setup              # packages only
mix snakebridge.setup --full       # includes runtime install if managed
mix snakepit.setup                 # separate, for full Snakepit needs
```

---

### Issue 9: Environment Flag Rationale

The design suggests:

```
PYTHONNOUSERSITE=1
PIP_DISABLE_PIP_VERSION_CHECK=1
PIP_NO_INPUT=1
```

These are correct, but incomplete. Add:

```
PIP_NO_WARN_SCRIPT_LOCATION=1   # Suppress PATH warnings
UV_NO_PROGRESS=1                # Clean CI logs
PYTHONDONTWRITEBYTECODE=1       # No .pyc files in venv
```

---

### Issue 10: Error Semantics for Missing Packages

The design doesn't specify what error structure is returned when packages are
missing.

**Recommendation**: Structured errors:

```elixir
{:error, %Snakepit.PackageError{
  type: :not_installed,
  packages: ["numpy", "scipy"],
  suggestion: "Run: mix snakebridge.setup"
}}

{:error, %Snakepit.PackageError{
  type: :version_mismatch,
  package: "numpy",
  required: "~=1.26",
  installed: "1.25.0",
  suggestion: "Run: mix snakebridge.setup --upgrade"
}}
```

## Architecture Decision

The design presents two components:

1. `Snakepit.PythonPackages` - Low-level installer (Snakepit-owned)
2. `SnakeBridge.PythonEnv` - High-level orchestrator (SnakeBridge-owned)

**Assessment**: This is the right split. It keeps Snakepit generic and puts
SnakeBridge-specific logic in SnakeBridge.

**One Adjustment**: The orchestrator should be simpler. It's essentially:

```elixir
defmodule SnakeBridge.PythonEnv do
  def ensure!(config) do
    if auto_install_enabled?(config) do
      requirements = derive_requirements(config.libraries)
      Snakepit.PythonPackages.ensure!({:list, requirements}, [])
    end
    :ok
  end
end
```

The complexity should live in `Snakepit.PythonPackages`, not the orchestrator.

## Recommended Changes

1. **Keep installer generic**: `PythonPackages` should not parse SnakeBridge
   config
2. **Use PEP-440 directly**: Avoid Elixir → Python version translation
3. **Add per-library install policy**: `:always`, `:dev`, `:optional`
4. **Use UV lockfile for hash**: Captures full resolution
5. **Defer staged installs**: Not MVP
6. **Add structured errors**: For missing/mismatched packages
7. **Clarify command hierarchy**: `snakebridge.setup` vs `snakepit.setup`

## Conclusion

The design is fundamentally sound. The ownership boundary is correct, the UV
choice is correct, and the lockfile extension is necessary. The issues above are
refinements, not fundamental problems.

The biggest implementation risk is the version constraint translation. Recommend
using PEP-440 directly to avoid a translation layer.
