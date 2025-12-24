# SnakeBridge Library Scaling Plan (2025-12-23)

## Purpose

This document captures the current SnakeBridge architecture and explains how it scales to add Python libraries quickly without growing core complexity. It also outlines a cleanup plan to remove per-library logic from core and make the add-a-library workflow tight, repeatable, and safe at scale.

This is written for the current repository state after the Snakepit 0.7.0 upgrade and the initial three-library target:
- sympy: symbolic math validation
- pylatexenc: LaTeX parsing for math grading
- math-verify: equivalence checks for math answers

## Current Architecture Snapshot

SnakeBridge is a manifest-driven wrapper around Snakepit. Manifests describe a curated allowlist of stateless functions, and the runtime uses a single generic adapter tool (call_python) to invoke Python through Snakepit.

High-level flow:

1) Manifests are loaded and validated.
2) Allowlist is registered.
3) Generator emits Elixir modules for those functions.
4) Runtime calls call_python through Snakepit.

In practice, some Python libraries do not return JSON-safe values. For those, the current system uses per-library Python bridge modules that normalize outputs into JSON-friendly shapes. Manifests reference the bridge using python_path_prefix.

## Key Components and Where They Live

### Manifests and Registry
- priv/snakebridge/manifests/*.json
- priv/snakebridge/manifests/_index.json
- lib/snakebridge/manifest/loader.ex
- lib/snakebridge/manifest/registry.ex

Manifests are small JSON files that define:
- python_module (import path)
- python_path_prefix (optional) for bridge routing
- functions (curated allowlist, args, return types)
- types (simple type hints for arguments)

### Runtime and Generator
- lib/snakebridge/runtime.ex
- lib/snakebridge/generator.ex
- lib/snakebridge/manifest.ex

Runtime is generic and does not embed library-specific logic. Generator builds Elixir functions from manifest data. Runtime enforces allowlist via the manifest registry.

### Python Adapter (generic)
- priv/python/snakebridge_adapter/adapter.py

This is the only generic Python adapter. It exposes tools such as describe_library and call_python and dispatches calls to Python code.

### Python Bridges (library-specific)
- priv/python/snakebridge_adapter/sympy_bridge.py
- priv/python/snakebridge_adapter/pylatexenc_bridge.py
- priv/python/snakebridge_adapter/math_verify_bridge.py
- priv/python/snakebridge_adapter/numpy_bridge.py

These are the current per-library conversion layers. They are referenced by manifest python_path_prefix and exist to serialize non-JSON-safe objects into strings/lists/maps.

### Elixir-side Adapter (library-specific)
- lib/snakebridge/adapters/numpy.ex

This is an Elixir convenience adapter built before the manifest-first flow stabilized. It is not required by the manifest system and is a candidate for removal or externalization.

### Examples and Tests
- examples/manifest_sympy.exs
- examples/manifest_pylatexenc.exs
- examples/manifest_math_verify.exs
- test/integration/real_python_libraries_test.exs
- test/integration/manifest_examples_test.exs

These demonstrate end-to-end usage of the built-in manifests with real Python.

## Why the Per-Library Bridges Exist

The core constraint is JSON serialization. Many Python libraries return objects that cannot be serialized by default (SymPy expressions, LaTeX AST nodes, NumPy arrays). The bridges exist to normalize results into safe shapes so the Elixir side can remain generic.

Examples:
- SymPy objects (Expr, Symbol, Equation) are converted into strings.
- pylatexenc nodes are converted into maps/lists of maps.
- math-verify returns booleans and lists of strings directly.

If a library is already JSON-safe (for example, json in stdlib), it can be called directly without a bridge.

## How It Scales Today (Without Cleanup)

Even with bridges in the core repo, the scale story is already mostly data-driven:

1) Create manifest
- Run mix snakebridge.discover <lib> to draft a manifest.
- Curate 10-30 stateless functions; keep it small.
- Save to priv/snakebridge/manifests/<lib>.json

2) Decide whether a bridge is needed
- If all return values are JSON-safe, no bridge needed.
- If not, add a small bridge module in priv/python/snakebridge_adapter/<lib>_bridge.py and set python_path_prefix.

3) Register manifest
- Add entry to priv/snakebridge/manifests/_index.json

4) Add example and test
- Add examples/manifest_<lib>.exs
- Add or extend integration tests to validate core calls

5) Install Python dependencies
- Ensure mix snakebridge.setup installs the Python package or document pip install.

This is already low friction, but the per-library bridges living in the core repo is the main scaling smell.

## Architectural Smells That Block Scaling

1) Per-library Python bridges in core
- This blurs the line between generic runtime and library integrations.
- It creates a central bottleneck for new library additions.

2) Elixir-side adapters in core
- lib/snakebridge/adapters/numpy.ex is a library-specific API surface.
- It bypasses the manifest-first approach and makes the core look library-aware.

3) No formal bridge contract
- We do not have a strict, documented interface for bridge inputs/outputs.
- This increases the review load for each new library.

4) Manifest path prefix couples to internal path
- python_path_prefix currently points into snakebridge_adapter.*
- This makes it hard to move bridges out of core without migration.

## Target Architecture for Clean Scaling

Goal: The core is 100 percent generic; adding a new library is data-only (manifest) plus optional external bridge.

### Target Boundaries

Core (SnakeBridge repo):
- Runtime, loader, generator, type mapper, registry
- Manifest tooling (discover, validate, check)
- No per-library adapters in Elixir

Library Packs (external or separate tree):
- Manifests
- Optional Python bridge modules
- Tests and examples

### Bridge Contract (Required)

Define a minimal bridge contract and enforce it:
- Inputs are JSON-serializable (dict/list/str/int/float/bool)
- Outputs must be JSON-serializable
- No global state or external I/O in bridge functions
- Bridge functions are pure and idempotent
- Bridge functions must accept named args only (kwargs)

### Standardized Manifest Conventions

- python_module: actual Python import path
- python_path_prefix: optional; points to bridge module
- functions: curated allowlist of stateless functions
- types: optional hints for args, limited to simple shapes

## Tight, Clean Add-a-Library Flow (Target)

1) Draft manifest
- mix snakebridge.discover <lib>
- Remove stateful or non-serializable functions
- Keep 10-30 functions max

2) Decide bridge
- If a function returns non-JSON output, implement a bridge function that returns strings/lists/maps
- Store bridge in external pack and point python_path_prefix to it

3) Validate
- mix snakebridge.manifest.validate <manifest>
- mix snakebridge.manifest.check --all

4) Test and example
- Add one example script
- Add one integration test per library

5) Publish
- Add manifest entry to index
- Update docs to include the library

## Cleanup Plan (Concrete Steps)

### Phase 0: Freeze
- No new per-library Elixir adapters in core
- No new per-library Python bridges in core

### Phase 1: Separate bridges
- Move priv/python/snakebridge_adapter/*_bridge.py to a new location (e.g., priv/python/bridges/ or an external repo)
- Update python_path_prefix in manifests to point to new bridge path
- Ensure PYTHONPATH includes bridge path

### Phase 2: Remove Elixir adapters
- Remove lib/snakebridge/adapters/numpy.ex from core
- Replace with a manifest example and tests

### Phase 3: Formalize contract
- Add a small document describing the bridge contract
- Add a test helper that validates bridge outputs are JSON-safe

### Phase 4: CI enforcement
- CI check fails if new modules are added under lib/snakebridge/adapters
- CI check fails if manifests point to internal bridge paths

### Phase 5: Packaging
- Create a separate repo or directory for "library packs":
  - manifests
  - bridges
  - examples
  - tests

## What This Means For the Three Initial Libraries

### sympy
- Current manifest routes through sympy_bridge
- Bridge converts SymPy objects into strings
- Works today; bridge should move out of core

### pylatexenc
- Current manifest routes through pylatexenc_bridge
- Bridge flattens LaTeX node objects into maps/lists
- Works today; bridge should move out of core

### math-verify
- Bridge exists but mostly unnecessary since outputs are already JSON-safe
- Can test direct calls after contract is enforced

## Risks and Constraints

- Some libraries will always require a bridge (SymPy, NumPy)
- Some libraries can be handled entirely by manifest (json, math)
- The current python_path_prefix model couples manifests to a module path; moving bridges requires a path migration plan
- Any bridge that leaks state breaks reproducibility; enforcing statelessness is critical

## Verification and Quality Gates

Standard checks for each new library:
- mix snakebridge.manifest.validate <manifest>
- mix snakebridge.manifest.check --all
- mix test --include integration --include real_python
- examples/manifest_<lib>.exs produces explicit outputs

## Summary

The architecture already scales if we treat manifests as data and bridges as optional, tiny normalization layers. The main blocker is that the bridges and a legacy Elixir adapter live inside the core repo, making the core appear library-aware. The cleanup plan separates those concerns and formalizes a bridge contract so we can add libraries at scale without contaminating the core.
