# SnakeBridge Build-Out Plan (Reality Adapted)

## Scope and Goals

- Deliver curated, manifest-driven integrations for sympy, pylatexenc, and math-verify.
- Use the manifest-driven pipeline (JSON manifests -> Manifest -> Generator).
- Ensure compatibility with Snakepit 0.7.0 and JSON-safe interop.
- Ship a simple user-facing config: `config :snakebridge, load: [:sympy, :pylatexenc, :math_verify]`.

## Current Reality Snapshot (Codebase)

- Discovery/introspection exists in `lib/snakebridge/discovery.ex` and
  `lib/snakebridge/discovery/introspector.ex`, using `describe_library` from the
  Python adapter (`priv/python/snakebridge_adapter/adapter.py`).
- Code generation is already implemented via `SnakeBridge.Generator` using
  `SnakeBridge.Manifest` as the input schema.
- Mix tasks for discover/validate/generate/clean already exist.
- Manifest loader and built-in curated library configs exist under `priv/snakebridge/manifests/`
  with `_index.json` as the registry.
- `SnakeBridge.Catalog` exists and includes sympy/pylatexenc/math-verify entries.
- The Python adapter uses a shared serializer; wrapper modules return JSON-safe values.
- Dev/test use `SnakeBridge.SnakepitMock` by default; real-python integration is optional.
- Dependency is now `snakepit ~> 0.7.0` and docs have been updated accordingly.

## Target State (MVP)

- Use JSON manifests as the source of truth (data-only).
- Ship curated manifests for sympy, pylatexenc, math-verify under `priv/`.
- Provide a loader so users can opt-in via config (load list or :all).
- Ensure return values are JSON-serializable and typespecs reflect conversions.
- Add real-python smoke tests and short examples.

## Architecture Mapping (Old Plan -> Current Code)

- `introspect.py` -> `SnakeBridge.Discovery` + `mix snakebridge.discover`
- `schema.json` -> optional raw schema artifact; manifest.json is the active config
- `Runtime.call()` -> `SnakeBridge.Runtime.call_function/4` and `call_method/4`
- `Generator` -> existing `SnakeBridge.Generator`
- `Loader` -> new `SnakeBridge.Manifest.Loader` (to add)
- `Agent` -> optional `SnakeBridge.Manifest.Agent` (later)

## Implementation Plan

### Phase 0: Snakepit 0.7.0 Alignment

- Verify `SnakeBridge.SnakepitAdapter` still matches `Snakepit.execute_in_session/4`
  and streaming functions in 0.7.0.
- Run one real-python smoke test against the local `../snakepit` build.
- Update README/SNAKEPIT setup docs to reflect 0.7.0 and current venv guidance.

### Phase 1: Manifest Layer (Core)

- Choose manifest location (recommend `priv/snakebridge/manifests/` to align with
  existing `priv/snakebridge/` namespace).
- Add `priv/snakebridge/manifests/_index.json` with metadata (name, module, version,
  category, status).
- Implement `SnakeBridge.Manifest`:
  - Parse simplified manifest format (python_module, version, category, functions,
    types, exclude).
  - Convert into `SnakeBridge.Config` struct.
  - Map `functions` entries into config descriptors (name, python_path, elixir_name,
    parameters, return_type).
- Update generator helpers to accept string return types in `build_return_spec/1`
  (or normalize to map format in the manifest parser).
- Add loader:
  - `SnakeBridge.Manifest.Loader.load/1` reads built-ins and `custom_manifests`.
  - `SnakeBridge.Application` calls loader at startup based on
    `config :snakebridge, load: [:sympy, ...]` or `load: :all`.
- Optional: add `mix snakebridge.manifests` to list built-in manifests.

### Phase 2: Serialization Safety (Shared)

- Add JSON-safe conversion in `priv/python/snakebridge_adapter/adapter.py`:
  - SymPy objects (`sympy.Basic`) -> `str(value)` (or `srepr` if we want stable output).
  - pylatexenc nodes -> recursive dict with `type`, `content`, and `children`.
  - Tuples -> lists; walk lists/dicts recursively.
  - Preserve primitives (str, int, float, bool, list, dict, nil).
- Apply conversion in `_call_module_function` and `_call_instance_method`.
- Add a small Python unit test (or tagged Elixir integration test) to validate
  serialization for at least one SymPy expression and one pylatexenc node.

### Phase 3: Library Integrations (Manifests)

#### SymPy

- Generate a draft via `mix snakebridge.discover sympy`.
- Curate to a small stateless set and set `elixir_module: SnakeBridge.SymPy`.
- Suggested functions:
  - `symbols/1`, `sympify/1`, `Eq/2`, `solve/2`
  - `simplify/1`, `expand/1`, `factor/1`, `diff/2`, `integrate/2`
  - `latex/1`, `N/2`
- Set return types to string/list/map as needed to match serializer output.

#### pylatexenc

- Module name: `SnakeBridge.PyLatexEnc`.
- Wrap class-based APIs so calls are stateless in Elixir:
  - `latex_to_text/1` uses `LatexNodes2Text().latex_to_text`.
  - `unicode_to_latex/1` uses `latexencode.unicode_to_latex`.
  - `parse/1` uses a small helper that returns a JSON AST (nodes -> maps).
- Implement wrapper functions in Python adapter or a small helper module under
  `priv/python/adapters/pylatexenc/`.

#### math-verify

- Confirm import name (likely `math_verify`) via discovery.
- Expose `parse/1`, `verify/2`, and `grade/2` (or `grader.grade/2`).
- Ensure parse output is JSON-safe (string or map) and verify returns boolean.
- Align versions with SymPy/pylatexenc to avoid dependency conflicts.

### Phase 4: Tests + Docs

- Add real-python smoke tests under `test/integration/real_python_*` tagged
  `:real_python`.
- Add examples in `examples/` for math grading flow.
- Update `README.md` to describe manifest loading and Snakepit 0.7.0 setup.
- Update `SnakeBridge.Catalog` entries for sympy, pylatexenc, math-verify.

### Phase 5: Optional Agent (Later)

- Implement `SnakeBridge.Manifest.Agent.suggest/1` that uses schema + heuristics
  to propose function lists.
- Store drafts under `priv/snakebridge/manifests/_drafts/` for human review.

## Library Function Sets (Initial Draft)

### SymPy

- `symbols(names, opts)` -> list/string
- `sympify(expr)` -> string
- `Eq(lhs, rhs)` -> string
- `solve(expr, symbol)` -> list
- `simplify(expr)` -> string
- `expand(expr)` -> string
- `factor(expr)` -> string
- `diff(expr, symbol)` -> string
- `integrate(expr, symbol)` -> string
- `latex(expr)` -> string
- `N(expr, precision)` -> float/string

### pylatexenc

- `latex_to_text(latex)` -> string
- `unicode_to_latex(text)` -> string
- `parse(latex)` -> list/map (JSON AST)

### math-verify

- `parse(text, opts)` -> string/map (normalized expression)
- `verify(gold, answer, opts)` -> boolean
- `grade(gold, answer, opts)` -> map/boolean

## Acceptance Criteria

- `config :snakebridge, load: [:sympy, :pylatexenc, :math_verify]` loads modules
  without runtime compile errors.
- Each library has at least 3-5 real-python smoke tests passing.
- Results are JSON-serializable; typespecs match actual return values.
- README and catalog reflect the new manifests and Snakepit 0.7.0.

## Risks / Open Questions

- math-verify API surface and return types need confirmation via discovery.
- pylatexenc AST serialization format may need design decisions.
- SymPy output format (string vs structured representation) affects grading.
- Runtime module generation can increase startup time; may need precompile in prod.
