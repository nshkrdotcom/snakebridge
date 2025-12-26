# Gap Analysis: SnakeBridge ↔ Snakepit

Status: Analysis
Date: 2025-12-25

## Overview

This document identifies specific disconnects between what SnakeBridge expects
from Snakepit and what Snakepit currently provides. The goal is to ensure the
two libraries integrate seamlessly.

## 1. Python Executable Resolution

### SnakeBridge Expects

```elixir
# lib/snakebridge/python_runner/system.ex:11-14
def run(script, args, opts) do
  with {:ok, python, _meta} <- Snakepit.PythonRuntime.resolve_executable() do
    # ...
  end
end
```

### Snakepit Provides

```elixir
# Snakepit.PythonRuntime.resolve_executable/0
# Returns {:ok, path, metadata} | {:error, reason}
# Metadata includes: python_version, python_platform, python_runtime_hash
```

### Gap: **None**

This integration point works correctly. SnakeBridge uses Snakepit's runtime
resolution and gets the correct Python binary.

---

## 2. Runtime Environment Variables

### SnakeBridge Expects

```elixir
# lib/snakebridge/python_runner/system.ex:26-32
defp build_env(opts) do
  base_env = Snakepit.PythonRuntime.runtime_env()
  extra_env = Application.get_env(:snakepit, :extra_env, %{})
  user_env = Keyword.get(opts, :env, %{})
  Map.merge(Map.merge(base_env, extra_env), user_env)
end
```

### Snakepit Provides

```elixir
# Snakepit.PythonRuntime.runtime_env/0
# Returns map with:
# - SNAKEPIT_PYTHON_RUNTIME_HASH
# - SNAKEPIT_PYTHON_VERSION
# - SNAKEPIT_PYTHON_PLATFORM
# - PATH (prepended with runtime bin dir)
```

### Gap: **None**

Environment variable injection works correctly.

---

## 3. Package Installation

### SnakeBridge Expects (Proposed)

```elixir
# From UV integration design
Snakepit.PythonPackages.ensure!(requirements, opts)
Snakepit.PythonPackages.installed?(requirements, opts)
Snakepit.PythonPackages.lock_metadata(requirements, opts)
```

### Snakepit Provides

**Nothing.** This module does not exist.

### Gap: **CRITICAL - Full Implementation Needed**

The `Snakepit.PythonPackages` module is proposed but not implemented. Currently:

1. **Bootstrap.ex** uses pip in a venv for `requirements.txt`
2. No UV-based package installation exists
3. No API for checking if packages are installed
4. No package metadata for lockfile

**Current Workaround**: Developers manually ensure packages are installed before
running SnakeBridge introspection.

---

## 4. Library → Python Package Mapping

### SnakeBridge Expects (Proposed)

```elixir
# Library config in mix.exs
libraries: [
  sympy: "~> 1.12",
  pylatexenc: "~> 2.10",
  math_verify: [
    version: "~> 0.1",
    pypi_package: "math-verify",  # <-- mapping
    extras: ["antlr"]
  ]
]
```

### Snakepit Provides

Nothing. This is a SnakeBridge concern.

### Gap: **SnakeBridge - Not Implemented**

The library config currently supports `python_name` for import resolution but
not `pypi_package` for pip/uv installation. These are different:

- `python_name: "numpy"` → `import numpy`
- `pypi_package: "math-verify"` → `pip install math-verify`

For most libraries these are the same, but for some (like `PIL` from `pillow`,
or `cv2` from `opencv-python`) they differ.

**Current Config Structure** (`lib/snakebridge/config.ex`):

```elixir
defmodule Config.Library do
  defstruct [
    :name,
    :version,        # pip version constraint
    :module_name,    # Elixir module name
    :python_name,    # Python import name
    :include,
    :exclude,
    :streaming,
    :submodules
    # MISSING: pypi_package, extras
  ]
end
```

---

## 5. Package Presence Detection

### SnakeBridge Expects (Proposed)

The design asks: "How should we detect package presence quickly without running
imports?"

### Snakepit Provides

Nothing directly. Could use:

```bash
uv pip show <package>
# or
python -c "import importlib.metadata; print(importlib.metadata.version('<package>'))"
```

### Gap: **CRITICAL - No Detection Mechanism**

Fast package detection is needed for:

1. Skipping install if already present
2. Validating environment before introspection
3. Computing package identity for lockfile

---

## 6. Environment Identity in Lockfile

### SnakeBridge Current

```json
// snakebridge.lock
{
  "environment": {
    "snakebridge_version": "0.4.0",
    "python_version": "3.12.3",
    "python_platform": "x86_64-pc-linux-gnu",
    "python_runtime_hash": "1319c137..."
  }
}
```

### SnakeBridge Expected (Proposed)

```json
{
  "environment": {
    "python_runtime_hash": "...",
    "python_version": "...",
    "python_platform": "...",
    "python_packages_hash": "sha256:..."  // <-- new
  },
  "python_packages": [
    "sympy~=1.12",
    "pylatexenc~=2.10"
  ]
}
```

### Gap: **Package Identity Not Tracked**

The current lockfile tracks Python runtime but not packages. This means:

1. Different machines with different package versions can generate different
   bindings
2. No way to detect if packages changed requiring regeneration
3. No reproducibility guarantee for package state

---

## 7. Introspection Failure Handling

### SnakeBridge Current

```elixir
# lib/snakebridge/introspector.ex
case System.cmd(python, ["-c", script | args], opts) do
  {output, 0} -> {:ok, Jason.decode!(output)}
  {output, _} -> {:error, {:introspection_failed, output}}
end
```

### Gap: **No Distinction Between "Package Missing" and "Other Error"**

When introspection fails, SnakeBridge can't tell if:

1. The package isn't installed (`ModuleNotFoundError`)
2. The package has import-time errors
3. The introspection script has a bug
4. Python itself crashed

This matters for:

- Auto-install logic (should we install? or is something else wrong?)
- Error messages (what should the developer do?)
- Strict mode (is this a "generation needed" case or a bug?)

---

## 8. Managed Runtime Installation

### SnakeBridge Expects (Proposed)

```elixir
SnakeBridge.PythonEnv.ensure!(config)
# Calls:
Snakepit.PythonRuntime.install_managed(version, opts)
Snakepit.PythonPackages.ensure!(requirements, opts)
```

### Snakepit Provides

```elixir
Snakepit.PythonRuntime.install_managed(version, opts)
# Works! Uses: uv python install <version>
```

### Gap: **Half Implemented**

Runtime installation exists. Package installation does not. The orchestration
layer (`SnakeBridge.PythonEnv`) is also missing.

---

## 9. Strict Mode Behavior

### SnakeBridge Current

```elixir
# lib/snakebridge/config.ex
defstruct [
  # ...
  strict: false,  # exists but behavior unclear
]
```

### SnakeBridge Expected (Proposed)

```
In CI with strict: true:
1. Load manifest
2. Scan project
3. If any symbols missing from manifest → FAIL with guidance
4. Never attempt introspection/generation
```

### Gap: **Behavior Not Fully Implemented**

The config option exists but:

1. The compiler still attempts introspection when symbols are missing
2. No clear error message guiding developers to run `mix snakebridge.setup`
3. No environment variable override (`SNAKEBRIDGE_STRICT=1`)

---

## 10. Bootstrap Workflow Conflict

### SnakeBridge Expects

Uses `Snakepit.PythonRuntime` for hermetic, UV-managed Python.

### Snakepit Current (Bootstrap.ex)

```elixir
def setup(opts) do
  # Creates .venv via python -m venv
  # Installs via pip install -r requirements.txt
  # NOT using UV for packages
end
```

### Gap: **Workflow Mismatch**

The proposed UV integration would create a second package installation path:

1. `Snakepit.Bootstrap.setup/1` → pip in venv (for Snakepit's own needs)
2. `Snakepit.PythonPackages.ensure!/2` → uv pip install (for SnakeBridge)

This could lead to:

- Two different Python environments
- Package version conflicts
- Confusion about which mechanism to use

**Recommendation**: Unify package installation under UV. `Bootstrap` should also
use `PythonPackages` internally.

---

## Summary Table

| Gap | Severity | Owner | Status |
|-----|----------|-------|--------|
| Package Installation API | Critical | Snakepit | Not started |
| Package Presence Detection | Critical | Snakepit | Not started |
| Library → PyPI Mapping | High | SnakeBridge | Not started |
| Package Identity in Lock | High | SnakeBridge | Not started |
| Introspection Error Types | Medium | SnakeBridge | Not started |
| PythonEnv Orchestrator | Medium | SnakeBridge | Not started |
| Strict Mode Enforcement | Medium | SnakeBridge | Partial |
| Bootstrap/UV Unification | Medium | Snakepit | Not started |

## Next Steps

1. Implement `Snakepit.PythonPackages` (see `04-implementation-plan.md`)
2. Extend SnakeBridge config for pypi_package mapping
3. Implement strict mode enforcement
4. Unify Bootstrap with PythonPackages
