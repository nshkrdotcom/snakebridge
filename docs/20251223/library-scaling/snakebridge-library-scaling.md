# SnakeBridge Library Scaling: Critical Review and v2 Plan (2025-12-23)

## Scope and Goal

Goal (original): integrate the first three Python libraries in a **clean, isolated, repeatable** way, so adding more libraries scales without core churn.

Reality: the three integrations work, but their code is spread across core, Python adapter, manifests, and tooling. The system is not yet “cleanly isolated” per library.

This document is a critical review of the current state and a minimal‑change plan to reach a robust scaling design.

Target libraries:
- sympy (symbolic math validation)
- pylatexenc (LaTeX parsing for grading)
- math-verify (equivalence checks)

## What Exists Today (Evidence, Not Preference)

### Manifest‑first flow (sound, keep it)
- Manifests define allowlisted functions and simple types.
- Loader validates + registers allowlists.
- Generator emits modules.
- Runtime calls generic `call_python` via Snakepit.

This is the correct backbone and should remain.

### Actual integration footprint per library (current)

Each new library currently touches **8+ locations**, which is the opposite of “isolated”:

1) Manifest
- `priv/snakebridge/manifests/<lib>.json`

2) Built‑in manifest index (duplicate metadata)
- `priv/snakebridge/manifests/_index.json`

3) Python dependencies list (duplicate metadata)
- `priv/python/requirements.snakebridge.txt`

4) Python bridge module (if serialization needed)
- `priv/python/snakebridge_adapter/<lib>_bridge.py`

5) Shared serializer with library‑specific branches
- `priv/python/snakebridge_adapter/serializer.py` (sympy / pylatexenc / numpy handling)

6) Catalog (duplicate metadata)
- `lib/snakebridge/catalog.ex`

7) Examples
- `examples/manifest_<lib>.exs`

8) Tests
- `test/integration/real_python_libraries_test.exs`
- `test/integration/manifest_examples_test.exs`

This is the concrete spread that breaks isolation.

## Critical Problems (Actual Design Issues)

### 1) Multiple Sources of Truth for library metadata (High)

Problem:
- Manifest, `_index.json`, `catalog.ex`, and `requirements.snakebridge.txt` all define library metadata (package name, version, description, status).
- They are not auto‑derived from each other.

Impact:
- Every new library requires updates in multiple places.
- Drift is likely and silent (a manifest can exist but not be discoverable via `_index.json`; catalog can diverge from actual manifests).

Evidence:
- Loader uses `_index.json` to resolve built‑ins (`lib/snakebridge/manifest/loader.ex`).
- Install task uses `_index.json` for pypi lookup if missing in manifest.
- `catalog.ex` duplicates all metadata again.

### 2) Library‑specific serialization in the core adapter (High)

Problem:
- `priv/python/snakebridge_adapter/serializer.py` contains **hardcoded SymPy / pylatexenc / NumPy** logic.

Impact:
- Core adapter is no longer generic.
- Adding a new library often requires editing serializer, which violates isolation and forces core changes.

### 3) Library‑specific Elixir adapter in core (Medium)

Problem:
- `lib/snakebridge/adapters/numpy.ex` is a library‑specific API surface in core.

Impact:
- Bypasses the manifest system and makes the core appear library‑aware.
- Creates a separate integration path that does not scale.

### 4) Bridge path coupling to internal module names (Medium)

Problem:
- Manifests point `python_path_prefix` into `snakebridge_adapter.*`.

Impact:
- Hard to move bridges out of core without breaking manifests.
- No clear boundary between core adapter and per‑library logic.

### 5) Requirements file is manual and redundant (Medium)

Problem:
- `priv/python/requirements.snakebridge.txt` lists built‑in libs manually.

Impact:
- New libraries require edits in yet another place.
- `mix snakebridge.manifest.install` already knows how to resolve packages from manifests, but `setup` uses the requirements file.

### 6) No enforced bridge contract (High)

Problem:
- Bridges are not required to implement a consistent interface or safety checks.
- Example: `math_verify_bridge.py` lacks `_ensure_math_verify()` guards, so its behavior is inconsistent with other bridges.

Impact:
- Bridge logic drifts and becomes fragile with each new library.
- Inconsistencies reappear as soon as library 4/5/6 land.

### 7) Redundant tests and CLI overlap (Medium)

Problem:
- `test/integration/manifest_examples_test.exs` overlaps `real_python_libraries_test.exs` almost exactly.
- `discover` / `manifest.gen` / `manifest.suggest` are three paths to similar output and create UX debt.

Impact:
- Test suite noise and longer maintenance tail.
- Users have too many entry points for the same action.

## What Is Working and Should Not Change

These parts are sound and should be preserved:
- Manifest allowlisting and runtime enforcement.
- Generator emitting modules from manifest data.
- Generic `call_python` tool as the single runtime path.
- Manifest tooling (discover/validate/check) — this is helpful and not the source of sprawl.

## v2 Plan (Big Bang, No Legacy Support)

The goal is **one source of truth** and **no per‑library logic in core**. This is a clean break, not a migration. All legacy artifacts are deleted, not deprecated.

### Step 1: Make the manifest the single source of truth (High)

Change:
- Add `pypi_package`, `description`, `status` directly into each manifest.
- **Delete `_index.json`**. Loader scans the manifests directory directly.
- **Delete `catalog.ex`**. Any catalog functionality reads from manifests at runtime.

Result:
- Removes 2 files and 2 manual edit points per library.

### Step 2: Move library‑specific serialization into bridges (High)

Change:
- **Strip `serializer.py` down to generic JSON‑safe primitives only** (None, str, int, float, bool, list, dict, bytes).
- **Delete all SymPy / pylatexenc / NumPy logic from serializer.py**.
- Each bridge calls its own serialization before returning.

Result:
- Core adapter becomes truly generic.
- New libraries never touch `serializer.py`.

### Step 3: Delete Elixir adapters from core (Medium)

Change:
- **Delete `lib/snakebridge/adapters/numpy.ex`**.
- **Delete the entire `lib/snakebridge/adapters/` directory**.

Result:
- One integration path: manifests only.
- No bypass mechanism exists.

### Step 3b: Remove library-specific types from TypeMapper (High)

Change:
- **Delete `normalize_numpy_ml_type/2`** function from `lib/snakebridge/type_system/mapper.ex`.
- **Delete `normalize_by_kind_numpy_ml/2`** function.
- **Delete all `do_to_elixir_spec` clauses** for `ndarray`, `dataframe`, `tensor`, `series`.
- **Remove references** to these types from `normalize_type_string/2`.

These types should be:
- Handled as `:any` or `term()` by default.
- Or defined in manifests if libraries need custom type mappings.

Result:
- TypeMapper is 100% generic.
- No library-specific knowledge in core type system.

### Step 4: Relocate bridges out of core adapter (Medium)

Change:
- **Move all `*_bridge.py` files** from `priv/python/snakebridge_adapter/` to `priv/python/bridges/`.
- **Update `python_path_prefix`** in all manifests to point to `bridges.<lib>_bridge`.
- **Update PYTHONPATH** in setup/launcher to include the bridges path.

Result:
- Clear boundary: `snakebridge_adapter/` is core, `bridges/` is per-library.

### Step 5: Delete requirements file (Medium)

Change:
- **Delete `priv/python/requirements.snakebridge.txt`**.
- **Update `mix snakebridge.setup`** to call `mix snakebridge.manifest.install --all` instead of reading a requirements file.

Result:
- Manifests are the only source for Python dependencies.
- One fewer file to maintain.

### Step 6: Delete redundant tests (Quick Win)

Change:
- **Delete `test/integration/manifest_examples_test.exs`**.

Result:
- `real_python_libraries_test.exs` provides full coverage.
- No duplicate test maintenance.

## v2 Definition of Done (Clear, Measurable)

A new library should require:
- **1 manifest file**
- **0 core code changes**
- **1 optional bridge file** (only if needed)
- **1 example + 1 test**

And it should not require:
- Editing `_index.json`
- Editing `catalog.ex`
- Editing `requirements.snakebridge.txt`
- Editing `serializer.py`

## Phase 2: Isolation Hardening (Post‑v2)

Phase 2 continues the big bang approach. No legacy support, no deprecation cycles.

### 2.1 Library Packs (Directory‑level isolation)

Change:
- **Restructure to one directory per library**: manifest + bridge + tests + examples together.
- **Delete the flat `priv/snakebridge/manifests/` structure**.
- **Delete the flat `priv/python/bridges/` structure** (from v2 Step 4).

New structure:
```
packs/sympy/manifest.json
packs/sympy/bridge.py
packs/sympy/test.exs
packs/sympy/example.exs
```

Result:
- A library is a self‑contained directory.
- Adding/removing a library = adding/removing one directory.

### 2.2 BridgeBase Contract (Enforcement)

Change:
- **Create `BridgeBase` class** with required interface: `ensure_available()`, `serialize()`.
- **Refactor all bridges to inherit from `BridgeBase`**.
- **Add CI check**: bridges that don't inherit from `BridgeBase` fail the build.

Result:
- Consistent safety checks across all bridges.
- No more missing `_ensure_*()` guards.

### 2.3 CLI Consolidation

Change:
- **Create `mix snakebridge.add <lib>`** as the single entry point.
- **Delete `mix snakebridge.discover`**.
- **Delete `mix snakebridge.manifest.gen`**.
- **Delete `mix snakebridge.manifest.suggest`**.

Result:
- One command to add a library.
- No confusion about which discovery task to use.

## Expected Outcome

After v2:
- Adding a new library = 1 manifest + 1 optional bridge + 1 test.
- Core is 100% generic. Zero library-specific code.
- No drift possible. Manifest is the only source of truth.

After Phase 2:
- Adding a new library = 1 directory with all files together.
- Bridges are contract-enforced. No inconsistent implementations.
- CLI has one obvious path.

## Appendix: Files Deleted in v2

| File | Step | Reason |
|------|------|--------|
| `priv/snakebridge/manifests/_index.json` | 1 | Replaced by directory scan |
| `lib/snakebridge/catalog.ex` | 1 | Duplicate of manifest data |
| `lib/snakebridge/adapters/numpy.ex` | 3 | Bypass mechanism |
| `lib/snakebridge/adapters/` (directory) | 3 | No adapters in core |
| `priv/python/requirements.snakebridge.txt` | 5 | Replaced by manifest.install |
| `test/integration/manifest_examples_test.exs` | 6 | Redundant coverage |

## Appendix: Files Modified in v2

| File | Step | Change |
|------|------|--------|
| `priv/python/snakebridge_adapter/serializer.py` | 2 | Strip to generic primitives only |
| `priv/snakebridge/manifests/*.json` | 1, 4 | Add metadata, update python_path_prefix |
| `lib/snakebridge/manifest/loader.ex` | 1 | Scan directory instead of reading _index.json |
| `lib/snakebridge/type_system/mapper.ex` | 3b | Remove ndarray/DataFrame/Tensor/Series handling |
| `lib/snakebridge/snakepit_launcher.ex` | 4 | Add bridges/ to PYTHONPATH |
| `lib/mix/tasks/snakebridge/setup.ex` | 5 | Call manifest.install instead of pip install -r |

## Appendix: Files Moved in v2

| From | To | Step |
|------|-----|------|
| `priv/python/snakebridge_adapter/sympy_bridge.py` | `priv/python/bridges/sympy_bridge.py` | 4 |
| `priv/python/snakebridge_adapter/pylatexenc_bridge.py` | `priv/python/bridges/pylatexenc_bridge.py` | 4 |
| `priv/python/snakebridge_adapter/math_verify_bridge.py` | `priv/python/bridges/math_verify_bridge.py` | 4 |
| `priv/python/snakebridge_adapter/numpy_bridge.py` | `priv/python/bridges/numpy_bridge.py` | 4 |

## Appendix: Files Deleted in Phase 2

| File/Directory | Step | Reason |
|----------------|------|--------|
| `priv/snakebridge/manifests/` | 2.1 | Replaced by packs structure |
| `priv/python/bridges/` | 2.1 | Replaced by packs structure |
| `lib/mix/tasks/snakebridge/discover.ex` | 2.3 | Replaced by `add` command |
| `lib/mix/tasks/snakebridge/manifest/gen.ex` | 2.3 | Replaced by `add` command |
| `lib/mix/tasks/snakebridge/manifest/suggest.ex` | 2.3 | Replaced by `add` command |

This is a clean break. No migration. No legacy support.
