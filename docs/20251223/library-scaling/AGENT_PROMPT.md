# Agent Prompt: SnakeBridge v2 Library Scaling Implementation

## Mission

Implement the v2 library scaling plan using TDD. Big bang approach—delete all legacy code, no migration support.

**Target version:** 0.3.1
**Date:** 2025-12-23

---

## Required Reading (Read These First)

### Primary Plan Document
```
docs/20251223/library-scaling/snakebridge-library-scaling.md
```
This is the authoritative plan. Follow it exactly.

### Secondary Reference (Deeper Analysis)
```
docs/20251223/library-scaling/snakebridge-library-scaling-v2.md
```
Contains additional context on why decisions were made.

### Current Source Files to Understand

**Manifests (will be modified):**
- `priv/snakebridge/manifests/sympy.json`
- `priv/snakebridge/manifests/pylatexenc.json`
- `priv/snakebridge/manifests/math_verify.json`
- `priv/snakebridge/manifests/_index.json` (will be DELETED)

**Python adapter and bridges:**
- `priv/python/snakebridge_adapter/adapter.py`
- `priv/python/snakebridge_adapter/serializer.py` (will be STRIPPED DOWN)
- `priv/python/snakebridge_adapter/sympy_bridge.py` (will be MOVED)
- `priv/python/snakebridge_adapter/pylatexenc_bridge.py` (will be MOVED)
- `priv/python/snakebridge_adapter/math_verify_bridge.py` (will be MOVED)
- `priv/python/snakebridge_adapter/numpy_bridge.py` (will be MOVED)

**Elixir core (will be modified):**
- `lib/snakebridge/manifest/loader.ex` (change to scan directory)
- `lib/snakebridge/catalog.ex` (will be DELETED)
- `lib/snakebridge/adapters/numpy.ex` (will be DELETED)
- `lib/snakebridge/type_system/mapper.ex` (remove ndarray/DataFrame/Tensor/Series)
- `lib/snakebridge/snakepit_launcher.ex` (add bridges to PYTHONPATH)

**Mix tasks (will be modified):**
- `lib/mix/tasks/snakebridge/setup.ex` (use manifest.install)

**Tests:**
- `test/integration/real_python_libraries_test.exs` (keep, may need path updates)
- `test/integration/manifest_examples_test.exs` (will be DELETED)

**Examples:**
- `examples/manifest_sympy.exs`
- `examples/manifest_pylatexenc.exs`
- `examples/manifest_math_verify.exs`
- `examples/run_all.sh`

---

## Implementation Steps (TDD Order)

Execute these steps in order. Each step: write/update tests first, then implement, then verify.

### Step 1: Delete `_index.json`, Make Loader Scan Directory

**Delete:**
- `priv/snakebridge/manifests/_index.json`

**Modify:**
- `lib/snakebridge/manifest/loader.ex` — scan `priv/snakebridge/manifests/*.json` directly instead of reading `_index.json`

**Update manifests** (add fields that were in `_index.json`):
- Each manifest gets: `pypi_package`, `description`, `status` fields

**TDD:**
1. Update/write tests in `test/unit/manifest_*_test.exs` to expect loader to work without `_index.json`
2. Run tests (they fail)
3. Implement changes
4. Run tests (they pass)

**Verify:**
```bash
mix test test/unit/manifest_test.exs
mix test test/unit/manifest_loader_test.exs
```

### Step 2: Delete `catalog.ex`

**Delete:**
- `lib/snakebridge/catalog.ex`

**Modify:**
- Any code that imports/uses `Catalog` must be updated or removed
- Search for: `SnakeBridge.Catalog`, `alias.*Catalog`, `Catalog.`

**TDD:**
1. Find all references to Catalog
2. Update tests to not use Catalog
3. Delete Catalog
4. Run tests

**Verify:**
```bash
mix test
grep -r "Catalog" lib/ test/
```

### Step 3: Strip `serializer.py` to Generic Primitives

**Modify:**
- `priv/python/snakebridge_adapter/serializer.py`

**Keep only:**
- `None`, `str`, `int`, `float`, `bool`, `bytes` → direct pass-through
- `list`, `tuple`, `set` → recursively convert elements
- `dict` → recursively convert values
- `complex` → `{"real": ..., "imag": ...}`
- Fallback → `str(value)`

**Delete from serializer.py:**
- All SymPy-specific handling
- All pylatexenc-specific handling (`_pylatexenc_node_to_dict`)
- All NumPy-specific handling

**Move to bridges:**
- Each bridge must call its own serialization before returning

**TDD:**
1. Run existing Python tests for serializer
2. Update bridges to handle their own serialization
3. Strip serializer
4. Run tests

**Verify:**
```bash
cd priv/python && python -m pytest
mix test --include real_python
```

### Step 4: Delete Elixir Adapters

**Delete:**
- `lib/snakebridge/adapters/numpy.ex`
- `lib/snakebridge/adapters/` (entire directory)

**Modify:**
- Remove any references to `SnakeBridge.Adapters.NumPy`
- Search for: `Adapters.NumPy`, `adapters/numpy`

**TDD:**
1. Find all references
2. Remove references
3. Delete files
4. Run tests

**Verify:**
```bash
mix test
grep -r "Adapters" lib/ test/
```

### Step 4b: Remove Library-Specific Types from TypeMapper

**Modify:**
- `lib/snakebridge/type_system/mapper.ex`

**Delete these functions:**
- `normalize_numpy_ml_type/2`
- `normalize_by_kind_numpy_ml/2`

**Delete these `do_to_elixir_spec` clauses:**
- `%{kind: "ndarray", ...}` clauses
- `%{kind: "dataframe"}` clause
- `%{kind: "tensor", ...}` clause
- `%{kind: "series"}` clause

**Remove references in:**
- `normalize_type_string/2` - remove the `normalize_numpy_ml_type` call

**Replace with:**
- Unknown types fall through to `:any` / `term()`

**TDD:**
1. Update type mapper tests to expect `:any` for ndarray/DataFrame/etc
2. Remove the library-specific functions
3. Run tests

**Verify:**
```bash
mix test test/unit/type_mapper_test.exs
grep -r "ndarray\|DataFrame\|Tensor\|Series" lib/
```

### Step 5: Move Bridges to `priv/python/bridges/`

**Create:**
- `priv/python/bridges/` directory
- `priv/python/bridges/__init__.py`

**Move:**
- `priv/python/snakebridge_adapter/sympy_bridge.py` → `priv/python/bridges/sympy_bridge.py`
- `priv/python/snakebridge_adapter/pylatexenc_bridge.py` → `priv/python/bridges/pylatexenc_bridge.py`
- `priv/python/snakebridge_adapter/math_verify_bridge.py` → `priv/python/bridges/math_verify_bridge.py`
- `priv/python/snakebridge_adapter/numpy_bridge.py` → `priv/python/bridges/numpy_bridge.py`

**Update manifests:**
- `python_path_prefix`: `"snakebridge_adapter.sympy_bridge"` → `"bridges.sympy_bridge"`
- Same for all other manifests

**Modify:**
- `lib/snakebridge/snakepit_launcher.ex` — add `priv/python/bridges` to PYTHONPATH

**TDD:**
1. Update manifests first
2. Move files
3. Update PYTHONPATH in launcher
4. Run integration tests

**Verify:**
```bash
mix test --include real_python
./examples/run_all.sh
```

### Step 6: Delete `requirements.snakebridge.txt`

**Delete:**
- `priv/python/requirements.snakebridge.txt`

**Modify:**
- `lib/mix/tasks/snakebridge/setup.ex` — call `mix snakebridge.manifest.install --all` instead of `pip install -r requirements.snakebridge.txt`

**TDD:**
1. Update setup task
2. Delete requirements file
3. Test setup flow manually

**Verify:**
```bash
rm -rf .venv
mix snakebridge.setup
mix test --include real_python
```

### Step 7: Delete Redundant Test File

**Delete:**
- `test/integration/manifest_examples_test.exs`

**Verify:**
```bash
mix test
```

---

## Final Verification Checklist

Run ALL of these. Every single one must pass with zero errors/warnings.

### Tests
```bash
mix test
mix test --include integration
mix test --include real_python
```

### Static Analysis
```bash
mix compile --warnings-as-errors
mix dialyzer
mix credo --strict
```

### Examples
```bash
./examples/run_all.sh
```

### Manual Smoke Test
```bash
# In iex:
iex -S mix
SnakeBridge.SymPy.simplify(%{expr: "sin(x)**2 + cos(x)**2"})
# Should return {:ok, "1"} or similar
```

---

## Version Bump

After all tests pass, update version to **0.3.1**:

### mix.exs
```elixir
@version "0.3.1"
```

### README.md
Update any version references.

### CHANGELOG.md
Add entry:
```markdown
## [0.3.1] - 2025-12-23

### Changed
- Manifest is now the single source of truth for library metadata
- Library-specific serialization moved from core to bridges
- Bridges relocated to `priv/python/bridges/`
- Setup task now uses `manifest.install` instead of requirements file

### Removed
- `_index.json` (loader scans manifest directory directly)
- `catalog.ex` (duplicate of manifest data)
- `lib/snakebridge/adapters/` (NumPy adapter and directory)
- `requirements.snakebridge.txt` (replaced by manifest.install)
- `manifest_examples_test.exs` (redundant test coverage)
```

---

## Documentation Updates

Update these docs to reflect the new structure:

- `docs/20251126/PYTHON_SETUP.md` — remove references to requirements.snakebridge.txt
- `examples/README.md` — update if needed
- `examples/QUICKSTART.md` — update if needed

---

## Success Criteria

All of these must be true:

- [ ] `mix test` — 0 failures
- [ ] `mix test --include integration` — 0 failures
- [ ] `mix test --include real_python` — 0 failures
- [ ] `mix compile --warnings-as-errors` — 0 warnings
- [ ] `mix dialyzer` — 0 errors
- [ ] `mix credo --strict` — 0 issues
- [ ] `./examples/run_all.sh` — all examples pass
- [ ] `_index.json` does not exist
- [ ] `catalog.ex` does not exist
- [ ] `lib/snakebridge/adapters/` does not exist
- [ ] `requirements.snakebridge.txt` does not exist
- [ ] `manifest_examples_test.exs` does not exist
- [ ] All bridges are in `priv/python/bridges/`
- [ ] `serializer.py` has no library-specific code
- [ ] `mapper.ex` has no ndarray/DataFrame/Tensor/Series handling
- [ ] `grep -r "ndarray\|DataFrame\|Tensor\|Series" lib/` returns nothing
- [ ] Version is 0.3.1 in mix.exs, README, CHANGELOG

---

## Constraints

- **No new features.** This is a cleanup/restructure only.
- **No migration support.** Delete, don't deprecate.
- **TDD.** Write/update tests before implementing.
- **Atomic commits.** One commit per step if possible.
- **No hedging.** If the plan says delete, delete it.
