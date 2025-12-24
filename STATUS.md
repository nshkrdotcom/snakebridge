# SnakeBridge Implementation Status

**Last Updated**: 2025-12-23
**Snakepit**: 0.7.0
**Test Results**: Unit + integration suites pass; real Python tests run with `mix test --only real_python`.

---

## Executive Summary

SnakeBridge is now a manifest-driven integration layer on top of Snakepit:
- Curated manifests ship for sympy, pylatexenc, and math-verify.
- Manifests generate Elixir modules at runtime or compile time.
- Streaming is supported via `call_python_stream` and generated `*_stream` wrappers.
- Tooling covers the full manifest workflow: discover, suggest, enrich, review, diff/check, lock, install, compile.

---

## ✅ Core Features (Implemented)

### Manifest System
- `SnakeBridge.Manifest` parses simplified manifests into `%SnakeBridge.Config{}`.
- `SnakeBridge.Manifest.Loader` loads built-in + custom manifests from globs.
- Built-in registry: `priv/snakebridge/manifests/_index.json`.
- Compile-time pipeline: `SnakeBridge.Manifest.Compiler` + `mix snakebridge.manifest.compile`.
- Lockfile support: `SnakeBridge.Manifest.Lockfile` + `mix snakebridge.manifest.lock`.
- Drift tooling: `mix snakebridge.manifest.diff` and `mix snakebridge.manifest.check`.
- Heuristic suggestions: `SnakeBridge.Manifest.Agent` + `mix snakebridge.manifest.suggest`.
- Enrichment: `mix snakebridge.manifest.enrich` (docstrings/types + cached schema).
- Review CLI: `mix snakebridge.manifest.review` (interactive curation).

### Code Generation + Runtime
- `SnakeBridge.Generator` builds function modules from manifests.
- `SnakeBridge.Manifest.Compiler` writes generated modules to `lib/snakebridge/generated`.
- `SnakeBridge.Application` respects `config :snakebridge, compilation_mode: :compile_time`.
- `SnakeBridge.Runtime` executes calls via Snakepit with telemetry and timeout handling.
- `SnakeBridge.Runtime.stream_function/4` + `stream_tool/4` support streaming tools.

### Python Adapter
- `describe_library` for introspection.
- `call_python` for module-level and instance calls.
- `call_python_stream` for streaming results.
- Shared JSON-safe serializer for SymPy, pylatexenc, and NumPy outputs.
- Curated wrappers for:
  - `snakebridge_adapter.sympy_bridge`
  - `snakebridge_adapter.pylatexenc_bridge`
  - `snakebridge_adapter.math_verify_bridge`
  - `snakebridge_adapter.numpy_bridge`

### Built-in Manifests (Phase 1)
- `sympy` -> `SnakeBridge.SymPy`
- `pylatexenc` -> `SnakeBridge.PyLatexEnc`
- `math_verify` -> `SnakeBridge.MathVerify`

### Mix Tasks
- `mix snakebridge.setup`
- `mix snakebridge.manifests`
- `mix snakebridge.manifest.gen`
- `mix snakebridge.manifest.suggest`
- `mix snakebridge.manifest.enrich`
- `mix snakebridge.manifest.review`
- `mix snakebridge.manifest.validate`
- `mix snakebridge.manifest.diff`
- `mix snakebridge.manifest.check`
- `mix snakebridge.manifest.lock`
- `mix snakebridge.manifest.install`
- `mix snakebridge.manifest.compile`
- `mix snakebridge.manifest.clean`

### Testing
- Real-Python integration tests boot Snakepit pools in-test.
- Python dependencies are auto-installed for test runs.
- Dedicated unit coverage for manifest parsing, diffing, streaming wrapper generation, and agent heuristics.

---

## Configuration Surface

```elixir
config :snakebridge,
  load: [:sympy, :pylatexenc, :math_verify],
  custom_manifests: ["config/snakebridge/*.json"],
  compilation_mode: :runtime,
  auto_start_snakepit: true,
  python_path: ".venv/bin/python3",
  pool_size: 4
```

---

## Notes / Next Steps

- Expand curated manifests as needed (community PRs welcome).
- Add CI guardrails to run `mix snakebridge.manifest.check` and `mix snakebridge.manifest.lock`.
- Continue to harden streaming adapters for additional libraries as they are added.
