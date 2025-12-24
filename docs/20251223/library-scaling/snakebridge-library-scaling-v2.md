# SnakeBridge Library Scaling: Critical Design Review (v2)

**Date:** 2025-12-23
**Status:** Critical Review
**Scope:** Architecture analysis after integrating sympy, pylatexenc, math-verify

---

## Executive Summary

The goal was to create **clean, isolated ways** to integrate Python libraries into Snakepit via SnakeBridge. Instead, the implementation **spread code across too many locations** with inconsistent patterns, creating a design that doesn't scale.

This document identifies the core architectural problems, provides concrete evidence, and proposes a cleaner v2 architecture.

---

## Part 1: What Went Wrong

### 1.1 The Spread Problem

Adding one Python library currently touches **7+ locations**:

| Location | Purpose | Example |
|----------|---------|---------|
| `priv/snakebridge/manifests/<lib>.json` | Declare functions | sympy.json |
| `priv/snakebridge/manifests/_index.json` | Register in catalog | Entry for sympy |
| `priv/python/snakebridge_adapter/<lib>_bridge.py` | Python wrapper | sympy_bridge.py |
| `priv/python/snakebridge_adapter/serializer.py` | Type conversion | SymPy.Basic → str |
| `priv/python/requirements.snakebridge.txt` | Dependencies | sympy>=1.13.0 |
| `examples/manifest_<lib>.exs` | Usage example | manifest_sympy.exs |
| `test/integration/real_python_libraries_test.exs` | Integration tests | SymPy tests |

This is **too spread out**. A single library integration shouldn't require touching 7 files across 4 directories.

### 1.2 The Duplication Problem

#### Manifest ↔ Index Duplication

The `_index.json` duplicates fields already in manifests:

```json
// _index.json
{
  "sympy": {
    "python_module": "sympy",      // Also in sympy.json
    "version": "~> 1.13",          // Also in sympy.json
    "category": "math",            // Also in sympy.json
    "description": "Symbolic math" // Also in sympy.json (sort of)
  }
}
```

**Problem:** Two sources of truth that can drift. When you update the version in one place, the other becomes stale.

#### Bridge Pattern Inconsistency

Each bridge implements safety checks differently:

```python
# sympy_bridge.py - GOOD: has safety check
def _ensure_sympy():
    if not HAS_SYMPY:
        raise ImportError("Install with: pip install sympy>=1.13.0")

def simplify(expr: str) -> str:
    _ensure_sympy()  # Called consistently
    ...

# math_verify_bridge.py - BAD: missing safety checks
def verify(gold: Any, answer: Any, **kwargs) -> Any:
    # NO _ensure_math_verify() call!
    if hasattr(math_verify, "verify"):
        return math_verify.verify(gold, answer, **kwargs)
```

**Problem:** No enforced contract. Each bridge is ad-hoc.

#### Test Duplication

Two test files test the same things:

| Function | manifest_examples_test | real_python_libraries_test |
|----------|------------------------|---------------------------|
| sympy.simplify | ✓ | ✓ |
| pylatexenc.latex_to_text | ✓ | ✓ |
| math_verify.grade | ✓ | ✓ |

`manifest_examples_test` is a **subset** of `real_python_libraries_test` with no additional value.

### 1.3 The Coupling Problem

#### Serializer Has Library-Specific Knowledge

The "generic" serializer knows about specific libraries:

```python
# serializer.py lines 42-58
def json_safe(value):
    ...
    # SymPy-specific handling
    if hasattr(value, '__class__') and value.__class__.__module__.startswith('sympy'):
        return str(value)

    # PyLatexEnc-specific handling
    if hasattr(value, 'nodetype'):
        return _pylatexenc_node_to_dict(value)
```

**Problem:** Adding a new library may require modifying the "generic" serializer.

#### TypeMapper Has Library-Specific Types

```elixir
# type_system/mapper.ex - hardcoded library types
"ndarray" -> {:ok, {:list, :float}}    # NumPy-specific
"DataFrame" -> {:ok, :map}              # pandas-specific
"Tensor" -> {:ok, {:list, :float}}      # ML framework-specific
"Series" -> {:ok, {:list, :any}}        # pandas-specific
```

**Problem:** The core type system embeds knowledge of specific libraries.

#### NumPy Adapter Bypasses Architecture

```elixir
# lib/snakebridge/adapters/numpy.ex
defmodule SnakeBridge.Adapters.NumPy do
  # Hardcoded module path
  @python_module "snakebridge_adapter.numpy_bridge"

  def array(data, opts \\ []) do
    # Bypasses manifest system entirely
    # Uses allow_unsafe: true to skip registry
    Runtime.call_function(@python_module, "array", %{data: data}, opts)
  end
end
```

**Problem:** This is a complete bypass of the manifest-driven architecture. It exists because the architecture was too painful to use correctly.

### 1.4 The CLI Confusion Problem

Too many overlapping tasks for discovery:

| Task | Purpose | Distinction |
|------|---------|-------------|
| `mix snakebridge.discover` | Generate manifest | Uses Agent.suggest_from_schema |
| `mix snakebridge.manifest.gen` | Generate manifest | Raw introspection |
| `mix snakebridge.manifest.suggest` | Generate manifest | Uses Agent.suggest_manifest |

**Problem:** Three ways to do the same thing with unclear differences.

Similarly for validation:

| Task | Purpose |
|------|---------|
| `mix snakebridge.validate` | Validate .exs configs (legacy) |
| `mix snakebridge.manifest.validate` | Validate JSON manifests |
| `mix snakebridge.manifest.check` | Validate against live Python |

**Problem:** Naming confusion and unclear responsibilities.

---

## Part 2: Root Cause Analysis

### 2.1 No Clear Library Package Boundary

The fundamental issue: **there's no concept of a "library package"** that bundles everything together.

Currently, library integration is scattered because there's no single unit that contains:
- The manifest
- The Python bridge (if needed)
- The serialization rules (if needed)
- The tests
- The examples

### 2.2 Bridge Contract is Implicit

There's no formal specification for what a bridge must do:

- **Input contract:** Must bridges accept only kwargs? Only JSON-safe types?
- **Output contract:** What shapes are allowed? Must it call serializer?
- **Error contract:** How should bridges report errors?
- **Safety contract:** Must bridges have `_ensure_*()` guards?

Each bridge author reinvents these decisions.

### 2.3 Manifest Schema is Underspecified

The manifest JSON format has grown organically:

```json
{
  "python_path_prefix": "snakebridge_adapter.sympy_bridge",  // What is this?
  "python_module": "sympy",                                   // vs this?
  "types": { ... },                                           // No schema
  "functions": [ ... ]                                        // Validation is weak
}
```

- `python_path_prefix` vs `python_module` confusion
- Type system has no formal definition
- Validation only checks field presence, not semantics

### 2.4 No Compile-Time Safety

Generated modules embed runtime config:

```elixir
@config unquote(Macro.escape(config))
```

If the config schema changes, all generated modules break. There's no versioning or migration path.

---

## Part 3: Evidence from the Codebase

### 3.1 Manifest System Issues

**Issue: Duplicate function definitions pass validation**

`pylatexenc.json` has the same function twice:
```json
{ "name": "parse_latex", "elixir_name": "parse", ... },
{ "name": "parse_latex", "elixir_name": "parse_latex", ... }
```

The validator doesn't catch this. What does the generator do with duplicates?

**Issue: python_path construction is complex**

From `manifest.ex:232-243`:
```elixir
defp default_python_path(manifest, python_name) do
  prefix = Map.get(manifest, :python_path_prefix) ||
           Map.get(manifest, "python_path_prefix") ||
           Map.get(manifest, :python_module) ||
           Map.get(manifest, "python_module")
  # ...
end
```

Four fallbacks because the schema doesn't enforce one source of truth.

### 3.2 Python Bridge Issues

**Issue: math_verify_bridge lacks safety guards**

```python
# Every public function should call this, but doesn't:
def _ensure_math_verify():
    if not HAS_MATH_VERIFY:
        raise ImportError("...")

def verify(gold, answer, **kwargs):
    # Missing: _ensure_math_verify()
    if hasattr(math_verify, "verify"):
        return math_verify.verify(gold, answer, **kwargs)
```

**Issue: Serializer fallback loses data silently**

```python
# serializer.py final fallback
return str(value)  # No warning, no logging
```

Complex objects become opaque strings with no indication of data loss.

### 3.3 Runtime Issues

**Issue: Streaming has three different mechanisms**

1. `Runtime.execute_stream()` - callback-based
2. `Runtime.stream_tool()` - Snakepit streaming
3. Generated `*_stream` functions - choose based on `streaming_tool` config

No documentation on when to use which.

**Issue: Registry bypass is easy**

```elixir
# Any code can bypass security with this flag:
Runtime.call_function(module, func, args, allow_unsafe: true)
```

The NumPy adapter uses this. What's the point of the registry if it's trivially bypassed?

### 3.4 Test Issues

**Issue: Assertions are too permissive**

```elixir
# This assertion accepts almost anything:
assert is_boolean(result) or is_map(result) or is_binary(result)
```

Tests pass even if the implementation is broken.

**Issue: Only ~30% of manifest functions are tested**

| Library | Functions in Manifest | Functions Tested |
|---------|----------------------|------------------|
| sympy | 21 | 4 (19%) |
| pylatexenc | 4 | 3 (75%) |
| math_verify | 3 | 3 (100%) |

---

## Part 4: Target Architecture (v2 Proposal)

### 4.1 The Library Pack Concept

Introduce a **library pack** as the unit of integration:

```
priv/snakebridge/packs/sympy/
├── manifest.json           # Function declarations
├── bridge.py               # Python wrapper (optional)
├── serializers.py          # Type conversions (optional)
├── test_spec.json          # Expected test behaviors
└── examples.exs            # Usage examples
```

**Benefits:**
- Everything for one library in one place
- Easy to add/remove libraries
- Clear ownership and review scope
- Can be distributed as separate packages

### 4.2 Formal Bridge Contract

Define a strict interface that all bridges must follow:

```python
# snakebridge_adapter/bridge_base.py

class BridgeBase:
    """All bridges must inherit from this."""

    LIBRARY_NAME: str  # Required: "sympy", "pylatexenc", etc.
    REQUIRED_PACKAGES: list[str]  # Required: ["sympy>=1.13.0"]

    @classmethod
    def ensure_available(cls) -> None:
        """Raises ImportError if library not installed."""
        raise NotImplementedError

    @staticmethod
    def serialize(value: Any) -> JsonSafe:
        """Convert library-specific types to JSON-safe values."""
        raise NotImplementedError
```

**Bridge implementation example:**

```python
# packs/sympy/bridge.py
from snakebridge_adapter.bridge_base import BridgeBase

class SymPyBridge(BridgeBase):
    LIBRARY_NAME = "sympy"
    REQUIRED_PACKAGES = ["sympy>=1.13.0"]

    _sympy = None

    @classmethod
    def ensure_available(cls):
        if cls._sympy is None:
            try:
                import sympy
                cls._sympy = sympy
            except ImportError:
                raise ImportError(f"Install with: pip install {cls.REQUIRED_PACKAGES[0]}")

    @staticmethod
    def serialize(value):
        if hasattr(value, '__class__') and 'sympy' in value.__class__.__module__:
            return str(value)
        return value

    def simplify(self, expr: str) -> str:
        self.ensure_available()
        result = self._sympy.simplify(self._sympy.sympify(expr))
        return self.serialize(result)
```

### 4.3 Simplified Manifest Schema

Remove redundant fields and enforce consistency:

```json
{
  "$schema": "snakebridge/manifest/v2",
  "library": {
    "name": "sympy",
    "version": "~> 1.13",
    "pypi_package": "sympy",
    "category": "math"
  },
  "bridge": {
    "module": "sympy_bridge",
    "class": "SymPyBridge"
  },
  "elixir": {
    "module": "SnakeBridge.SymPy"
  },
  "functions": [
    {
      "name": "simplify",
      "python_name": "simplify",
      "params": [
        {"name": "expr", "type": "string", "required": true}
      ],
      "returns": {"type": "string"},
      "doc": "Simplify a mathematical expression"
    }
  ]
}
```

**Changes from v1:**
- Single `library` block (no duplication with _index.json)
- Explicit `bridge` block (no `python_path_prefix` confusion)
- Parameters have explicit `required` flag
- Schema version for future migrations

### 4.4 Remove _index.json

The index should be **derived**, not authored:

```elixir
# At compile time or runtime:
def build_index(packs_dir) do
  packs_dir
  |> Path.join("*/manifest.json")
  |> Path.wildcard()
  |> Enum.map(&read_manifest/1)
  |> Enum.into(%{}, fn m -> {m.library.name, m} end)
end
```

**Benefits:**
- No duplication to maintain
- No drift between index and manifests
- Single source of truth

### 4.5 Consolidated CLI

Reduce to 5 essential commands:

| Command | Purpose |
|---------|---------|
| `mix snakebridge.setup` | One-time environment setup |
| `mix snakebridge.add <lib>` | Add a library (discover → generate → compile) |
| `mix snakebridge.list` | List installed libraries |
| `mix snakebridge.check` | Validate all libraries against live Python |
| `mix snakebridge.remove <lib>` | Remove a library |

The `add` command is the **single entry point** that orchestrates:
1. Install Python package
2. Introspect API
3. Generate manifest draft
4. Optional: interactive review
5. Compile to Elixir modules
6. Validate

### 4.6 Remove Library-Specific Code from Core

**TypeMapper:** Remove hardcoded types

```elixir
# Before (bad):
"ndarray" -> {:ok, {:list, :float}}
"DataFrame" -> {:ok, :map}

# After (good):
# Type mapping defined in library pack manifest
defp custom_type_mapping(pack_config, type_name) do
  Map.get(pack_config.type_mappings, type_name, :any)
end
```

**Serializer:** Move library-specific logic to bridges

```python
# Before (bad): serializer.py knows about SymPy
if 'sympy' in value.__class__.__module__:
    return str(value)

# After (good): bridge handles its own serialization
# serializer.py is truly generic, calls bridge.serialize()
```

**Adapters:** Delete `lib/snakebridge/adapters/numpy.ex`

This module is a design smell. If the manifest system is too painful to use, fix the manifest system rather than bypassing it.

---

## Part 5: Migration Plan

### Phase 1: Consolidate (No Breaking Changes)

1. **Create library pack structure** in `priv/snakebridge/packs/`
2. **Move existing bridges** from `snakebridge_adapter/*_bridge.py` to packs
3. **Keep old paths working** via symlinks or imports
4. **Delete manifest_examples_test.exs** (redundant with real_python_libraries_test.exs)

### Phase 2: Enforce Contract

1. **Create BridgeBase class** with required interface
2. **Refactor bridges to inherit** from BridgeBase
3. **Add bridge validation** in mix tasks
4. **Add _ensure_*() calls** to math_verify_bridge.py

### Phase 3: Simplify CLI

1. **Create `mix snakebridge.add`** that wraps the full workflow
2. **Deprecate** discover/gen/suggest with warnings
3. **Remove deprecated tasks** after one release cycle

### Phase 4: Remove Core Coupling

1. **Move type mappings** to pack manifests
2. **Move serialization logic** to bridges
3. **Delete NumPy Elixir adapter**
4. **Remove library-specific types** from TypeMapper

### Phase 5: Derive Index

1. **Generate _index.json** from manifests at compile time
2. **Remove manual _index.json** editing from workflow
3. **Update documentation** to reflect derived index

---

## Part 6: What This Means for Each Library

### sympy

| Current | Target |
|---------|--------|
| Manifest in `priv/snakebridge/manifests/` | Move to `packs/sympy/manifest.json` |
| Bridge in `snakebridge_adapter/` | Move to `packs/sympy/bridge.py` |
| Serialization in central serializer | Move to bridge.serialize() |
| Works today | Works after migration |

### pylatexenc

| Current | Target |
|---------|--------|
| Duplicate function definitions | Remove duplicate, keep one |
| Thin bridge (43 lines) | May not need bridge at all |
| Serialization in central serializer | Move to bridge or remove |

### math-verify

| Current | Target |
|---------|--------|
| Missing _ensure_math_verify() calls | Add safety guards |
| Defensive API probing | Document which API is expected |
| Outputs mostly JSON-safe | May not need bridge |

---

## Part 7: Success Metrics

After implementing v2, adding a new library should:

1. **Touch 2 files max:** `packs/<lib>/manifest.json` and optionally `packs/<lib>/bridge.py`
2. **Require no core changes:** No edits to serializer, TypeMapper, or core modules
3. **Take < 15 minutes:** From `mix snakebridge.add <lib>` to working functions
4. **Be fully tested:** Pack includes test spec that validates automatically

---

## Conclusion

The current design works for 3 libraries but won't scale to 30. The code is spread across too many locations with inconsistent patterns and implicit contracts.

The v2 architecture fixes this by:
1. **Introducing library packs** as the unit of integration
2. **Enforcing a bridge contract** with a base class
3. **Simplifying the manifest schema** to remove redundancy
4. **Consolidating the CLI** to a single add command
5. **Removing library-specific code** from the core

The migration can happen incrementally without breaking existing functionality.
