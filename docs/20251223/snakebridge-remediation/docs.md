# SnakeBridge Remediation Plan (Architecture Cleanup)

Date: 2025-12-23
Owner: SnakeBridge team
Scope: manifest pipeline, Python adapter boundaries, NumPy integration, runtime lifecycle, serialization

---

## 0) Executive Summary

SnakeBridge has multiple parallel integration paths and adapter variants. This is already causing real breakage (NumPy tool calls not registered in the default adapter). The remediation goal is to collapse into a single, deterministic integration pipeline and a single Python adapter surface, with library-specific behavior provided only by wrapper modules (not by bespoke tool registries or specialized adapters). This reduces drift, makes testing deterministic, and makes new library integrations trivial.

## 0.5) Status Update (2025-12-23)

**Resolved**
- Single adapter + wrapper modules (`numpy_bridge`, `sympy_bridge`, `pylatexenc_bridge`, `math_verify_bridge`) with centralized `serializer.py`.
- JSON manifests + `_index.json` registry; no `Code.eval_file` on manifests/lockfiles.
- Allowlist enforcement in `Runtime` with `allow_unsafe` escape hatch.
- Stable session ID generator shared across runtime/introspection/generator.
- Streaming envelope standardized (`success` + `data` chunks + `done` sentinel).
- Explicit instance cleanup via `release_instance/2`.
- Cache path moved to temp directory with safe deserialization.

**Open / Partial**
- Dynamic atom creation remains in parts of discovery/generator/manifest tasks.
- `compilation_mode` is primary, but `compilation_strategy` remains for compatibility.
- Timeouts still rely on Snakepit worker timeouts (no explicit cancellation signal).
- Introspector still bypasses Runtime telemetry and allowlist.
- Config surface still advertises unused features (mixins/extends/etc).
- Metadata duplication between Catalog and `_index.json` persists.

---

## 1) Current State (Observed)

### 1.1 Parallel Pipelines
- Legacy config-driven discovery/generation (`SnakeBridge.Discovery` + `SnakeBridge.Config` + `mix snakebridge.discover`) still exists alongside the new manifest pipeline.
- Both generate modules, which multiplies maintenance and test effort.

### 1.2 Adapter Fragmentation
- `SnakeBridgeAdapter` in `priv/python/snakebridge_adapter/adapter.py` only registers `describe_library`, `call_python`, `call_python_stream`.
- A separate `NumpyAdapter` in `priv/python/adapters/numpy/adapter.py` registers `np_*` tools, but the Snakepit pool does not load it.
- The Elixir `SnakeBridge.Adapters.Numpy` calls `np_*` tools directly, which fails under the default adapter (real skip currently observed in tests).

### 1.3 Serialization Inconsistency
- Serialization logic exists in multiple places:
  - `SnakeBridgeAdapter._json_safe` handles SymPy and pylatexenc.
  - `sympy_bridge.py` and `pylatexenc_bridge.py` also perform JSON-safe conversions.
  - `NumpyAdapter` defines its own `_json_safe` logic.
- Output shape and behavior differ based on which path is invoked.

### 1.4 Runtime Lifecycle Side Effects
- The runtime can auto-start Snakepit and install Python dependencies on-demand.
- Runtime calls are no longer pure; behavior depends on environment state and package installation availability.

### 1.5 Foundational Smells (Expanded Review)
- **No allowlist enforcement / trust boundary.** `call_python` accepts any `module_path` + `function_name`, and `SnakeBridge.Runtime` never checks loaded manifests. This means any Python module reachable on `PYTHONPATH` is effectively callable, bypassing curation and serializer expectations. (Files: `priv/python/snakebridge_adapter/adapter.py`, `lib/snakebridge/runtime.ex`.)
- **Manifests are executable code.** `Code.eval_file` is used for manifests, `_index.json`, and lockfiles, which is RCE if manifests come from PRs or user input and makes builds non-deterministic. (Files: `lib/snakebridge/manifest.ex`, `lib/snakebridge/manifest/loader.ex`, `lib/snakebridge/manifest/lockfile.ex`, mix tasks.) **Status: resolved** (JSON manifests + safe parser).
- **Dynamic atom creation from external input.** `String.to_atom` appears on module and function names derived from manifests/introspection, which can leak atoms and crash the VM on long-running systems. (Files: `lib/snakebridge/discovery.ex`, `lib/snakebridge/manifest/agent.ex`, `lib/snakebridge/manifest/lockfile.ex`, `lib/snakebridge/generator.ex`.)
- **Low-entropy session IDs + inconsistent generators.** Multiple modules generate session IDs with `:rand.uniform(100_000)` and different prefixes. Collisions are plausible under load and across nodes. (Files: `lib/snakebridge/runtime.ex`, `lib/snakebridge/discovery/introspector.ex`, `lib/snakebridge/generator.ex`.) **Status: resolved** (SessionId).
- **Runtime code generation in production path.** `Generator.generate_all/1` compiles modules at runtime, and compile-time hooks reference `SnakeBridge.Generator.Hooks` which does not exist. There are two strategy flags (`compilation_mode` and `compilation_strategy`) that disagree. (Files: `lib/snakebridge/generator.ex`, `lib/snakebridge/application.ex`.) **Status: partial** (hooks stub added; compilation_mode primary, legacy retained).
- **Cache writes into priv + unsafe deserialization.** The default cache path is `priv/snakebridge/cache`, which is read-only in releases; deserialization uses `:erlang.binary_to_term` without `:safe`. (File: `lib/snakebridge/cache.ex`.) **Status: resolved** (temp cache + safe deserialization).
- **Timeouts do not cancel Python work.** `execute_with_timeout` only kills the Elixir Task; the Python call continues running, which can leak CPU/memory and hold instances. (File: `lib/snakebridge/runtime.ex`.)
- **Introspection bypasses runtime contracts.** `SnakeBridge.Discovery.Introspector` calls the adapter directly, bypassing `Runtime` telemetry and timeout policy. (File: `lib/snakebridge/discovery/introspector.ex`.)
- **Streaming response contract mismatch.** `call_python_stream` yields chunks without `success` flags, while non-streaming calls depend on `success` and `result` keys. This is a protocol inconsistency. (File: `priv/python/snakebridge_adapter/adapter.py`.) **Status: resolved** (enveloped stream + done sentinel).
- **Stateful instance lifecycle is implicit.** Instances are created and stored in Python with TTL-based cleanup, but there is no explicit Elixir API to release or track them. This conflicts with the "stateless-only" story. (Files: `priv/python/snakebridge_adapter/adapter.py`, `lib/snakebridge/runtime.ex`.) **Status: resolved** (release_instance).
- **Config surface exceeds implementation.** `SnakeBridge.Config` advertises gRPC, caching, bidirectional tools, telemetry, mixins/extends, but most are unused in runtime/generator, inviting drift and confusion. (File: `lib/snakebridge/config.ex`.)
- **Metadata duplication and drift.** Library metadata lives in `SnakeBridge.Catalog`, `_index.json`, and manifest files with no enforcement of consistency. (Files: `lib/snakebridge/catalog.ex`, `priv/snakebridge/manifests/_index.json`.)

---

## 2) Remediation Principles (Non-Negotiable)

1. **Single Source of Truth**: Manifests drive all integrations. Legacy config pipeline becomes read-only legacy and then deprecated.
2. **Single Python Adapter**: One adapter class registered with Snakepit. No per-library adapter swapping.
3. **No Tool Name Explosion**: Library functions are called via `call_python` using wrapper modules, not custom tool names.
4. **One Serializer**: JSON-safe conversion belongs in one shared layer, reused by all wrapper modules.
5. **Explicit Runtime Lifecycle**: Runtime should not install Python deps or decide to start pools by default.
6. **Enforced Allowlist**: Manifests define what is callable; runtime rejects anything else unless explicitly unsafe.
7. **Manifests Are Data**: No `Code.eval_file` in production paths; manifests must be data-only.
8. **Stable IDs + Safe Metadata**: Central session ID generator; no unbounded atom creation from external input.
9. **Explicit Cancellation + Lifecycle**: Timeouts cancel Python work; instance lifecycles are observable and releasable.

---

## 3) Target Architecture

### 3.1 System Shape

```
Elixir Manifest (.json) -> Manifest Loader -> Generator -> Module
                                         \-> Runtime.call_function
Python Adapter (SnakeBridgeAdapter)
    - describe_library
    - call_python
    - call_python_stream

Python Wrapper Modules (priv/python/snakebridge_adapter/*.py)
    - sympy_bridge
    - pylatexenc_bridge
    - math_verify_bridge
    - numpy_bridge   (new)

Serializer (single source)
    - adapter uses it
    - wrappers use it
```

### 3.2 Python Call Flow

```
Elixir: SnakeBridge.SymPy.solve(%{expr: "x**2 - 1", symbol: "x"})
 -> Runtime.call_function("snakebridge_adapter.sympy_bridge.solve", "solve", kwargs)
 -> SnakeBridgeAdapter.call_python
 -> sympy_bridge.solve(...)
 -> serializer.json_safe
 -> JSON-safe response
```

No `np_*` tools are registered. NumPy is just another wrapper module called via `call_python`.

---

## 4) Detailed Remediation Work

### 4.1 Unify Pipeline Around Manifests

**Goal**: Manifests are the only active integration route.

**Changes**:
- Update `mix snakebridge.discover` to emit a draft manifest (not `SnakeBridge.Config`).
- Mark `SnakeBridge.Config` / legacy generator as deprecated (log warning if used).
- Update docs to reflect manifests as the primary workflow.

**Files**:
- `lib/mix/tasks/snakebridge/discover.ex`
- `lib/snakebridge/discovery.ex`
- `lib/snakebridge/config.ex` (deprecation note)
- `README.md` / `docs/PYTHON_SETUP.md`

**Acceptance**:
- `mix snakebridge.discover sympy` creates a manifest file in `priv/snakebridge/manifests/_drafts/` or user-specified output.
- All internal examples and docs show manifest workflow only.

---

### 4.2 Replace NumPy Tool Registration With Wrapper Module

**Goal**: Remove `np_*` tool dependency and use standard `call_python` path.

**Changes**:
- Create `priv/python/snakebridge_adapter/numpy_bridge.py` with functions:
  - `array`, `zeros`, `ones`, `arange`, `linspace`, `mean`, `sum`, `dot`, `reshape`, `transpose`.
- Ensure wrapper returns `{"data": ..., "shape": ..., "dtype": ...}` for arrays and `{"result": ...}` for scalar ops.
- Update Elixir `SnakeBridge.Adapters.Numpy` to call `Runtime.call_function` on `snakebridge_adapter.numpy_bridge` instead of `np_*` tools.
- Remove `priv/python/adapters/numpy/adapter.py` or mark it legacy.

**Files**:
- `priv/python/snakebridge_adapter/numpy_bridge.py` (new)
- `lib/snakebridge/adapters/numpy.ex`
- `priv/python/adapters/numpy/adapter.py` (remove or deprecate)
- `priv/python/snakebridge_adapter/__init__.py` (export numpy_bridge if needed)

**Acceptance**:
- `mix test --include real_python` passes NumPy tests without “Unknown tool” skips.
- No `np_*` tool names exist in the codebase outside of legacy/deprecated paths.

---

### 4.3 Centralize Serialization

**Goal**: One serializer used by adapter and wrappers.

**Changes**:
- Extract JSON-safe conversion into `priv/python/snakebridge_adapter/serializer.py`.
- Adapter and all wrapper modules call `serializer.json_safe`.
- Remove duplicate conversions where possible.

**Files**:
- `priv/python/snakebridge_adapter/serializer.py` (new)
- `priv/python/snakebridge_adapter/adapter.py`
- `priv/python/snakebridge_adapter/sympy_bridge.py`
- `priv/python/snakebridge_adapter/pylatexenc_bridge.py`
- `priv/python/snakebridge_adapter/math_verify_bridge.py`
- `priv/python/snakebridge_adapter/numpy_bridge.py`

**Acceptance**:
- One serialization path for SymPy, pylatexenc, and NumPy values.
- No wrapper defines its own private `_json_safe`.

---

### 4.4 Remove Runtime Side-Effects (Optional but Recommended)

**Goal**: Runtime execution should not provision Python or start pools implicitly.

**Changes**:
- Make auto-start optional default: `auto_start_snakepit: false` for prod.
- Move dependency installation entirely to `mix snakebridge.setup` / `mix snakebridge.manifest.install`.
- Keep a `SnakepitLauncher` helper for mix tasks and tests only.

**Files**:
- `lib/snakebridge/snakepit_adapter.ex`
- `lib/snakebridge/snakepit_launcher.ex`
- `docs/PYTHON_SETUP.md` / `README.md`

**Acceptance**:
- Production environments do not auto-install or auto-start; behavior is explicit.

---

### 4.5 Catalog Alignment

**Goal**: Catalog reflects actual adapter behavior.

**Changes**:
- Mark NumPy as manifest/wrapper based, not “generic adapter” or “specialized adapter.”
- Update `adapter_config` to always return the base adapter class.

**Files**:
- `lib/snakebridge/catalog.ex`

---

### 4.6 Enforce Allowlist / Trust Boundary

**Goal**: Manifests are authoritative; runtime rejects calls not in the curated surface.

**Changes**:
- Build a registry of exported functions from loaded manifests (module + function + arity).
- `SnakeBridge.Runtime.call_function/4` validates against the registry before calling `call_python`.
- Python adapter optionally enforces `snakebridge_adapter.*` module paths only.
- Add an explicit `allow_unsafe: true` escape hatch for advanced users (opt-in, default false).

**Files**:
- `lib/snakebridge/runtime.ex`
- `lib/snakebridge/manifest/loader.ex` (registry population)
- `lib/snakebridge/manifest/registry.ex` (new)
- `priv/python/snakebridge_adapter/adapter.py`

**Acceptance**:
- Calls to non-manifested functions return a deterministic error.
- Unsafe mode is explicit and clearly documented.

---

### 4.7 Make Manifests Data-Only (Remove `Code.eval_file`)

**Goal**: Manifests are safe, deterministic data.

**Changes**:
- Introduce a data format (`manifest.json` or `manifest.toml`) and a strict parser.
- Keep restricted `.exs` support for backward compatibility (warn + explicit flag).
- Update mix tasks to read data manifests, not evaluate code.

**Files**:
- `lib/snakebridge/manifest.ex`
- `lib/snakebridge/manifest/loader.ex`
- `lib/snakebridge/manifest/lockfile.ex`
- `lib/mix/tasks/snakebridge/*` (manifest tasks)

**Acceptance**:
- `Code.eval_file` is removed from runtime and mix tasks.
- Loading manifests cannot execute arbitrary code.

---

### 4.8 Centralize Session ID Generation

**Goal**: Collision-resistant, consistent session IDs everywhere.

**Changes**:
- Add `SnakeBridge.SessionId.generate/1` using `System.unique_integer([:positive, :monotonic])` or UUID.
- Replace `:rand.uniform` usage in runtime, generator, and introspector.

**Files**:
- `lib/snakebridge/runtime.ex`
- `lib/snakebridge/generator.ex`
- `lib/snakebridge/discovery/introspector.ex`
- `lib/snakebridge/session_id.ex` (new)

**Acceptance**:
- No `:rand.uniform` remains in session ID creation.

---

### 4.9 Fix Cache Path + Safe Serialization

**Goal**: Cache is writable in releases and safe to deserialize.

**Changes**:
- Default cache path to `System.tmp_dir!/snakebridge` or configurable under `:cache_path`.
- Use `:erlang.binary_to_term(..., [:safe])` or move to JSON.

**Files**:
- `lib/snakebridge/cache.ex`

**Acceptance**:
- Cache works in release environments without write errors.
- No unsafe deserialization in default paths.

---

### 4.10 Shrink Config Surface + Unify Compile Strategy

**Goal**: Remove dead options and unify compile-time behavior.

**Changes**:
- Remove or explicitly mark unused fields in `SnakeBridge.Config` (grpc, bidirectional_tools, caching, telemetry, mixins, extends).
- Choose one compile strategy key and delete the other; implement `SnakeBridge.Generator.Hooks` or remove the hook.

**Files**:
- `lib/snakebridge/config.ex`
- `lib/snakebridge/application.ex`
- `lib/snakebridge/generator.ex`

**Acceptance**:
- Config fields map to real behavior.
- Compile strategy is consistent and hook references are valid.

---

### 4.11 Standardize Response Envelope (Streaming + Non-Streaming)

**Goal**: One response contract for all calls.

**Changes**:
- Make streaming yield `{"success": true, "data": ...}` and a final `{"success": true, "done": true}` (or equivalent).
- Ensure errors always include `success: false` and `error` keys.
- Normalize in `SnakeBridge.Runtime` so both streaming and non-streaming paths are predictable.

**Files**:
- `priv/python/snakebridge_adapter/adapter.py`
- `lib/snakebridge/runtime.ex`
- `lib/snakebridge/stream.ex`

**Acceptance**:
- Streaming clients can consume a single envelope format without special cases.

---

### 4.12 Add Cancellation on Timeout

**Goal**: Timeouts stop Python work, not just Elixir tasks.

**Changes**:
- Add a cancellation tool or session-kill path in Snakepit (if supported).
- On timeout, send cancel signal and release session/instance resources.

**Files**:
- `lib/snakebridge/runtime.ex`
- `lib/snakebridge/snakepit_adapter.ex`
- `priv/python/snakebridge_adapter/adapter.py` (if a cancel tool is needed)

**Acceptance**:
- Timing out a call stops Python execution and frees resources.

---

### 4.13 Explicit Instance Lifecycle

**Goal**: Stateful instances have explicit creation and release APIs.

**Changes**:
- Add a `Runtime.release_instance/1` or `Runtime.delete_instance/1`.
- Add a Python tool to remove stored instances.
- Document instance lifecycle and discourage use outside explicit stateful libraries.

**Files**:
- `lib/snakebridge/runtime.ex`
- `priv/python/snakebridge_adapter/adapter.py`
- `docs/PYTHON_SETUP.md` / `README.md`

**Acceptance**:
- Instances can be explicitly released from Elixir.

---

## 5) Migration Strategy

1. **Phase 1 (safe)**: Add numpy wrapper + update Elixir adapter + tests. Keep legacy adapter file but unused.
2. **Phase 2**: Centralize serializer and remove duplicate conversions.
3. **Phase 3**: Deprecate config pipeline (log warnings, docs update).
4. **Phase 4**: Delete legacy adapter and config path after one release cycle.

---

## 6) Testing Plan

- `mix test` (unit)
- `mix test --include integration` (manifest + runtime coverage)
- `mix test --include real_python` (sympy/pylatexenc/math_verify/numpy)
- `mix snakebridge.manifest.check --all`

Add/Update Tests:
- Update NumPy integration tests to call `Runtime.call_function` path.
- Add a serialization test for NumPy arrays (shape/dtype + data values).

---

## 7) Risks + Mitigations

- **Risk**: Removing NumpyAdapter breaks existing deployments relying on `np_*` tools.
  - Mitigation: Keep `NumpyAdapter` for one release with deprecation warnings.

- **Risk**: Changing runtime lifecycle surprises users.
  - Mitigation: Keep `auto_start_snakepit` true by default in dev/test, false in prod; document clearly.

- **Risk**: Serializer consolidation changes return shape for edge cases.
  - Mitigation: Add regression tests for SymPy/pylatexenc/NumPy outputs.

- **Risk**: Enforcing allowlists breaks ad-hoc `call_python` usage.
  - Mitigation: Provide an explicit `allow_unsafe: true` escape hatch and document it as unsupported in prod.

- **Risk**: Changing manifest format affects existing manifests.
  - Mitigation: Provide a migration task and keep restricted `.exs` support behind a deprecation flag for one release.

---

## 8) Definition of Done

- NumPy tests pass without “Unknown tool” skips.
- Only one adapter class is required for all library calls.
- Manifests are the only documented integration workflow.
- Serialization behavior is consistent across wrapper and adapter paths.
- Runtime provisioning is explicit (no silent pip installs in production).
- Runtime enforces manifest allowlists by default.
- Manifests are loaded as data, not evaluated code.
- Session IDs are centralized and collision-resistant.
- Cache paths are release-safe and deserialization is safe.
- Timeouts cancel Python execution, not just Elixir tasks.

---

## 9) Open Questions

- Should NumPy integration be exposed via a manifest (like SymPy) or remain a bespoke Elixir adapter module?
- Should `mix snakebridge.discover` emit manifests directly, or create a draft + review flow by default?
- Do we want to support multiple pools (per-library) in the future, or commit to one adapter forever?
- Do we allow an "unsafe" escape hatch for direct `call_python`, or remove it entirely?
- What manifest data format should become canonical (JSON vs TOML vs strict Elixir data)?

---

## 10) Implementation Checklist

- [ ] Add `priv/python/snakebridge_adapter/numpy_bridge.py` with wrapper functions.
- [ ] Update `lib/snakebridge/adapters/numpy.ex` to call `Runtime.call_function` on wrapper module paths.
- [ ] Remove / deprecate `priv/python/adapters/numpy/adapter.py`.
- [ ] Add `serializer.py` and refactor all wrappers + adapter to use it.
- [ ] Update catalog metadata for NumPy.
- [ ] Update docs to remove references to `np_*` tools and specialized NumPy adapter.
- [ ] Run test suite and fix regressions.
