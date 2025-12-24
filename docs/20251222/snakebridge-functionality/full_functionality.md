# SnakeBridge Functionality (Full Inventory)

This document summarizes all functionality added across the extended SnakeBridge build session: manifest system, tooling, runtime/streaming, Python adapter, built-in libraries, and tests.

---

## 1) Manifest System (Curated, Opt-In)

### Manifest Format
- JSON manifests stored under `priv/snakebridge/manifests/` (string keys only).
- Keys: `name`, `python_module`, `python_path_prefix`, `version`, `category`, `elixir_module`, `types`, `functions`.
- Functions specify `args`, `returns`, optional `doc`, `streaming`, and `streaming_tool`.
- Legacy `.exs` manifests are supported via a restricted literal parser (no `Code.eval_file`).

### Built-in Registry
- `priv/snakebridge/manifests/_index.json` registers built-in manifests with metadata (pypi package, version, category, status).

### Loader
- `SnakeBridge.Manifest.Loader` resolves built-ins and custom globs from config.
- `load_configured/0` loads manifests based on `config :snakebridge, load: ...`.
- `resolve_manifest_files/2` supports `:all` or list of names, plus custom paths.
- Loader reads `_index.json` and registers an allowlist of functions/classes.
- If you generate modules manually, call `SnakeBridge.Manifest.Registry.register_config/1` to populate the allowlist.

### Compiler
- `SnakeBridge.Manifest.Compiler` compiles manifests into generated Elixir files.
- Output default: `lib/snakebridge/generated` (override with `--output`).

### Lockfile
- `SnakeBridge.Manifest.Lockfile` produces `priv/snakebridge/manifest.lock.json` with pinned package versions.

### Drift + Validation
- `SnakeBridge.Manifest.Diff` compares manifest function list vs live introspection.
- `mix snakebridge.manifest.check` fails CI on drift.
- `mix snakebridge.manifest.validate` validates manifest structure.

### Enrichment
- `mix snakebridge.manifest.enrich` hydrates functions with docstrings, args, return types, and merges types map.
- Supports cached schema storage under `priv/snakebridge/schemas`.

### Suggestions + Review
- `SnakeBridge.Manifest.Agent` suggests curated function lists via heuristics.
- `mix snakebridge.manifest.review` provides interactive keep/drop workflow.

---

## 2) Code Generation + Runtime

### Generator
- `SnakeBridge.Generator` builds modules for function manifests.
- Generated functions include specs and docstrings.
- Streaming functions generate `*_stream` wrappers.

### Runtime
- `SnakeBridge.Runtime` provides:
  - `execute/4`, `execute_with_timeout/4`
  - `call_function/4` for module-level calls
  - `create_instance/4` and `call_method/4` for instance methods
  - `stream_tool/4` and `stream_function/4` for streaming tools
  - `release_instance/2` to explicitly release Python instances
- Telemetry: `[:snakebridge, :call, :start|:stop|:exception]`.
- Generated functions accept a map of kwargs and return `{:ok, result}` / `{:error, reason}`.
- `SnakeBridge.SnakepitAdapter` auto-starts the Snakepit pool when missing (disable with `auto_start_snakepit: false`).
- Allowlist enforcement: manifest-defined functions/classes are allowed by default; `allow_unsafe: true` bypasses.

### Compile-Time vs Runtime Load
- `config :snakebridge, compilation_mode: :compile_time` skips runtime manifest loading.
- Use `mix snakebridge.manifest.compile` to emit compile-time modules.

---

## 3) Python Adapter

### Tools
- `describe_library` (introspection)
- `call_python` (module-level, instance, and class init calls)
- `call_python_stream` (streaming results)
- `release_instance` (explicit instance cleanup)

### Serialization
- Central JSON-safe conversion in `priv/python/snakebridge_adapter/serializer.py` for:
  - SymPy objects -> strings
  - pylatexenc nodes -> nested dicts
  - NumPy arrays -> JSON-friendly metadata + data
  - bytes -> utf-8 strings
  - tuples/sets -> lists

### Library Bridges
- `snakebridge_adapter.sympy_bridge`
- `snakebridge_adapter.pylatexenc_bridge`
- `snakebridge_adapter.math_verify_bridge`
- `snakebridge_adapter.numpy_bridge`

---

## 4) Built-in Libraries (Phase 1)

### SymPy (`SnakeBridge.SymPy`)
- Symbolic math helpers: `solve`, `simplify`, `expand`, `diff`, `integrate`, `latex`, `subs`, `free_symbols`, `n`, `factor`, and trig/log/exp helpers.

### pylatexenc (`SnakeBridge.PyLatexEnc`)
- LaTeX parsing/encoding: `latex_to_text`, `unicode_to_latex`, `parse`, `parse_latex`.

### math-verify (`SnakeBridge.MathVerify`)
- Math answer validation: `parse`, `verify`, `grade` (boolean).

---

## 5) Mix Tasks

### Setup + Discovery
- `mix snakebridge.setup` - Create venv and install Python deps.
- `mix snakebridge.discover` - Introspect and emit schema output.
- `mix snakebridge.manifests` - List built-in manifests.

### Manifest Lifecycle
- `mix snakebridge.manifest.gen` - Draft manifest from schema.
- `mix snakebridge.manifest.suggest` - Curated suggestion (heuristic).
- `mix snakebridge.manifest.enrich` - Docstring/type hydration.
- `mix snakebridge.manifest.review` - Interactive keep/drop.
- `mix snakebridge.manifest.validate` - Manifest validation.
- `mix snakebridge.manifest.diff` - Compare vs live schema.
- `mix snakebridge.manifest.check` - Fail CI on drift.

### Packaging + Compile
- `mix snakebridge.manifest.install` - Install Python packages for manifests.
- `mix snakebridge.manifest.lock` - Pin versions to lockfile.
- `mix snakebridge.manifest.compile` - Compile manifests to `.ex` files.
- `mix snakebridge.manifest.clean` - Clean + recompile generated modules.

---

## 6) Python Environment + Dependencies

- `priv/python/requirements.snakebridge.txt` includes sympy/pylatexenc/math-verify.
- `SnakeBridge.Python` provides venv/pip helpers for Mix tasks.
- Tests auto-install Python deps for real integration runs.

---

## 7) Streaming Support

- `call_python_stream` tool streams results from Python.
- Manifest functions with `streaming: true` generate `*_stream` wrappers.
- `streaming_tool` lets you bind to a custom Python streaming tool.

---

## 8) Testing

- Unit tests for manifest parsing, diff, agent heuristics, streaming wrappers.
- Real-Python integration tests for sympy/pylatexenc/math-verify.
- Test helper auto bootstraps Snakepit pool and Python dependencies.

---

## 9) Configuration (Key Settings)

```elixir
config :snakebridge,
  load: [:sympy, :pylatexenc, :math_verify],
  custom_manifests: ["config/snakebridge/*.json"],
  compilation_mode: :runtime,
  allow_unsafe: false,
  auto_start_snakepit: true,
  python_path: ".venv/bin/python3",
  pool_size: 4
```

---

## 10) File/Module Map

### Elixir
- `lib/snakebridge/manifest.ex`
- `lib/snakebridge/manifest/loader.ex`
- `lib/snakebridge/manifest/compiler.ex`
- `lib/snakebridge/manifest/lockfile.ex`
- `lib/snakebridge/manifest/diff.ex`
- `lib/snakebridge/manifest/agent.ex`
- `lib/snakebridge/generator.ex`
- `lib/snakebridge/runtime.ex`
- `lib/snakebridge/python.ex`
- `lib/mix/tasks/snakebridge/manifest/*.ex`

### Python
- `priv/python/snakebridge_adapter/adapter.py`
- `priv/python/snakebridge_adapter/sympy_bridge.py`
- `priv/python/snakebridge_adapter/pylatexenc_bridge.py`
- `priv/python/snakebridge_adapter/math_verify_bridge.py`

---

## 11) Suggested CI Checks

- `mix snakebridge.manifest.check --all`
- `mix snakebridge.manifest.lock --all`
- `mix test`
- `mix test --only real_python` (optional in CI, depends on Python availability)
