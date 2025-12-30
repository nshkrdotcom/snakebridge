# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.4] - 2025-12-30

### Added
- `SnakeBridge.Bytes` struct for explicit binary data encoding to Python `bytes`
- `SnakeBridge.SerializationError` exception for unsupported type encoding
- Tagged dict wire format for maps with non-string keys (integers, tuples, etc.)
- Auto-session: BEAM processes automatically get session IDs without explicit `with_session/1`
- `SnakeBridge.Runtime.current_session/0` to get current session ID
- `SnakeBridge.Runtime.release_auto_session/0` for explicit session cleanup
- `SnakeBridge.Runtime.clear_auto_session/0` for testing
- `SnakeBridge.SessionManager.unregister_session/1` to unregister without Python-side release
- Universal FFI: `SnakeBridge.call/4` now accepts string module paths for dynamic Python calls
- Universal FFI: `SnakeBridge.stream/5` accepts string module paths
- Universal FFI: `SnakeBridge.get/3` for module attributes with string paths
- `SnakeBridge.call!/4`, `SnakeBridge.get!/3`, `SnakeBridge.method!/4`, `SnakeBridge.attr!/3` bang variants
- `SnakeBridge.method/4` as alias for `Dynamic.call/4`
- `SnakeBridge.attr/3` as alias for `Dynamic.get_attr/3`
- `SnakeBridge.set_attr/4` as alias for `Dynamic.set_attr/4`
- `SnakeBridge.bytes/1` convenience function for creating Bytes wrappers
- `SnakeBridge.ref?/1` to check if a value is a Python ref
- `SnakeBridge.Runtime.stream_dynamic/5` for streaming with string module paths
- Python adapter: `_is_json_safe()` validation function as safety net for encode results
- New `universal_ffi_example` showcasing all Universal FFI features

### Changed
- Updated `dynamic_dispatch_example` with new convenience APIs (`SnakeBridge.call/4`, etc.)
- Updated `types_showcase` with `SnakeBridge.Bytes` and non-string key map examples
- Updated `session_lifecycle_example` with auto-session demonstration
- Encoder now raises `SerializationError` instead of silently calling `inspect/1` on unknown types
- Maps with non-string keys are now encoded as tagged dicts with key-value pairs
- Session ID is now always included in wire payloads (auto-generated if not explicit)
- `SnakeBridge.call/4` now dispatches to `call_dynamic/4` when given string module path
- Python adapter now unconditionally ref-wraps non-JSON-serializable return values
- Improved Python `encode()` to explicitly mark unencodable values with `__needs_ref__`
- Added JSON safety validation in `encode_result()` as a safety net

### Fixed
- Maps with integer/tuple keys now serialize correctly instead of coercing keys to strings
- Memory leaks from refs in "default" session when not using explicit `SessionContext`
- Ref collisions between unrelated Elixir processes
- Lists/dicts containing non-serializable items now properly return refs
- Eliminated partial/lossy encoding of complex Python objects

## [0.7.3] - 2025-12-30

### Added
- **Universal FFI Core**:
    - `SnakeBridge.Dynamic` module for method dispatch (`call`, `get_attr`, `set_attr`) on un-generated refs.
    - `SnakeBridge.Runtime.call_dynamic/4` to invoke arbitrary Python functions without compile-time scanning.
    - `SnakeBridge.ModuleResolver` to automatically disambiguate classes from submodules during compilation.
    - `SnakeBridge.SessionManager` and `SessionContext` for process-bound Python object lifecycle management.
    - `SnakeBridge.StreamRef` implementing `Enumerable` for lazy iteration over Python generators/iterators.
    - `SnakeBridge.WithContext.with_python/2` macro for Python context manager (`with` statement) support.
    - `SnakeBridge.CallbackRegistry` to pass Elixir functions into Python as callable callbacks.
- **Protocol Integration**:
    - `Inspect`, `String.Chars`, and `Enumerable` protocol implementations for `SnakeBridge.Ref`.
    - `SnakeBridge.DynamicException` to automatically map unknown Python exceptions to Elixir structs.
    - `SnakeBridge.Runtime.get_module_attr/3` for accessing module-level constants and objects.
- **Configuration**:
    - `config/wheel_variants.json` support via `SnakeBridge.WheelConfig` for externalized PyTorch wheel selection.
    - `SNAKEBRIDGE_ATOM_CLASS` environment variable to opt-in to legacy `Atom` object wrapping.

### Changed
- **Type System**:
    - Python atom decoding now defaults to plain strings for compatibility with standard libraries.
    - Unknown Python return types now automatically return a Ref handle instead of a string representation.
    - Runtime boundary now enforces strict encoding/decoding of all arguments and results.
- **Signature Model**:
    - Manifest now supports arity ranges (min/max) to correctly match calls with optional arguments.
    - C-extension functions (without inspectable signatures) now generate variadic wrappers (up to 8 args).
    - Required keyword-only arguments are now validated at runtime with clear error messages.
    - Function and method names are sanitised (e.g., `class` -> `py_class`) while preserving Python mapping.
- **Introspection**:
    - Unified introspection logic into a standalone `priv/python/introspect.py` script (removed embedded string script).
    - Introspection now captures module attributes and detects protocol-supporting dunder methods.
- **Telemetry**:
    - Standardized compile events under `[:snakebridge, :compile, phase, :start|:stop]`.
    - Unified metadata schema for compile events (`library`, `phase`, `details`).
- **Python Adapter**:
    - Added thread locks to global registries for concurrency safety.
    - Implemented session-scoped cleanup to prevent memory leaks on Elixir process exit.

### Fixed
- **Manifest correctness**: Fixed mismatch where scanner reported call-site arity while manifest stored required arity, causing perpetual "missing" symbols.
- **File Generation**: Fixed potential race conditions in `write_if_changed` using global locking.
- **Registry**: `SnakeBridge.Registry` is now properly populated and saved during the compilation phase.
- **Lockfile**: Generator hash now reflects actual source content rather than just the version string.

## [0.7.2] - 2025-12-29

### Added
- Wire schema version tagging and atom tags across Elixir/Python with tolerant decoding for legacy keys
- Protocol version markers on runtime payloads with adapter compatibility checks
- `SnakeBridge.Ref` schema plus `release_ref`/`release_session` runtime helpers
- `error_mode` configuration for translated or raised runtime errors
- Ref registry TTL/LRU controls in the Python adapter (`SNAKEBRIDGE_REF_TTL_SECONDS`, `SNAKEBRIDGE_REF_MAX`)
- Telemetry emission for scan, introspection, generate, docs fetch, and lock verification
- `protocol_payload/0` and `normalize_args_opts/2` helpers in `SnakeBridge.Runtime` for runtime payload consistency
- Example failure tracking helper to hard-fail on unexpected demo errors
- `SNAKEBRIDGE_ALLOW_LEGACY_PROTOCOL` toggle for protocol compatibility checks

### Changed
- Manifest symbol keys normalized without `Elixir.` prefixes and migrated on load
- Strict verification now validates class modules, methods, and attributes via AST parsing
- Dotted python library roots handled consistently in submodule generation and runtime metadata
- Generated wrappers accept extra positional args via `args \\ []` and emit typed specs
- Helper generation now writes only when content changes; Mix compiler reports manifest/lock artifacts
- Protocol compatibility is strict by default; legacy payloads require `SNAKEBRIDGE_ALLOW_LEGACY_PROTOCOL=1`
- Generated wrappers normalize keyword lists passed as args into opts when opts are omitted
- Example runners now raise on Snakepit script failures instead of printing and continuing
- Docs showcase fetches docstrings via the Python runner instead of raw runtime payloads

### Fixed
- Async scan/introspection task failures now surface structured errors instead of crashing
- Snakepit lockfile now aligns with the declared `~> 0.8.3` requirement
- Example payloads include protocol metadata to avoid version mismatches
- Wrapper/streaming/class constructor examples no longer fail JSON encoding for keyword options

## [0.7.1] - 2025-12-29

### Changed
- Upgrade snakepit dependency from 0.8.1 to 0.8.2
- Example runner (`run_all.sh`) now updates all dependencies upfront before running examples
- Example runner now fails fast on compilation errors instead of silently continuing

### Fixed
- Telemetry event paths updated from `[:snakepit, :call, :*]` to `[:snakepit, :python, :call, :*]` to align with snakepit 0.8.2
- RuntimeForwarder test setup now handles already-attached handlers gracefully

## [0.7.0] - 2025-12-28

### Added
- **Wrapper argument surface fix**: All generated wrappers now accept `opts \\ []` for runtime flags (`idempotent`, `__runtime__`, `__args__`) and Python kwargs
- **Streaming generation**: Functions in `streaming:` config now generate `*_stream` variants with proper `@spec`
- **Strict mode verification**: Now verifies generated files exist and contain expected functions
- **Documentation pipeline**: Docstrings are converted from RST/NumPy/Google style to ExDoc Markdown
- **Telemetry emission**: Compile pipeline now emits `[:snakebridge, :compile, :start|:stop|:exception]` events

### Changed
- Class constructors now match Python `__init__` signatures instead of hardcoded `new(arg, opts)`
- File writes use atomic temp files with unique names for concurrency safety
- File writes skip when content unchanged (no more mtime churn)

### Fixed
- Functions with `POSITIONAL_OR_KEYWORD` defaulted parameters now accept opts
- `VAR_POSITIONAL` parameters are now recognized for opts enablement
- Classes with 0, 2+, or optional `__init__` args now construct correctly

### Developer Experience
- New examples: `wrapper_args_example`, `class_constructor_example`, `streaming_example`, `strict_mode_example`
- Updated `run_all.sh` with new examples

## [0.6.0] - 2025-12-27

### Added
- `Docs.RstParser` for Google, NumPy, Sphinx, and Epytext docstring parsing
- `MarkdownConverter` to transform parsed docstrings into ExDoc markdown with type mappings
- `MathRenderer` for reStructuredText math directives (`:math:`, `.. math::`) to KaTeX format
- `ErrorTranslator` for structured Python exception translation with actionable suggestions
- `ShapeMismatchError` for tensor dimension parsing with transposition/broadcasting guidance
- `OutOfMemoryError` for device memory stats and recovery steps (CUDA, MPS)
- `DtypeMismatchError` for precision conflict detection with casting guidance
- `:telemetry` instrumentation for scan, introspect, generate, and runtime calls
- `RuntimeForwarder` to enrich Snakepit execution events with SnakeBridge context
- `Handlers.Logger` and `Handlers.Metrics` for compilation timing logs and standard metrics
- Hardware identity in `snakebridge.lock` (accelerator, CUDA version, GPU count, CPU features)
- `mix snakebridge.verify` to validate lock files against current runtime hardware
- `WheelSelector` for hardware-specific PyTorch wheel resolution (cu118, cu121, rocm, cpu)
- `examples/` with 8 demo projects covering docs, types, errors, telemetry, and performance
- `benchmarks/compile_time_benchmark.exs` for scan and generation performance tracking

### Changed
- `TypeMapper` now emits specific typespecs for `numpy.ndarray`, `torch.Tensor`, and `pandas.DataFrame`
- Suppress noisy OTLP/TLS logs during application startup

### Dependencies
- Requires snakepit ~> 0.8.1

## [0.5.0] - 2025-12-25

### Added
- `SnakeBridge.PythonEnv` module for Python environment orchestration
- `SnakeBridge.EnvironmentError` for missing package errors
- `SnakeBridge.IntrospectionError` for classified introspection failures
- `mix snakebridge.setup` task for provisioning Python packages
- Config options: `pypi_package`, `extras` per library
- Config option: `auto_install` (:never | :dev | :always)
- Strict mode enforcement via `SNAKEBRIDGE_STRICT=1` or `strict: true`
- Package identity in `snakebridge.lock` (`python_packages`, `python_packages_hash`)

### Changed
- Compiler now calls `PythonEnv.ensure!/1` before introspection (when not strict)
- Improved introspection error messages with fix suggestions

### Dependencies
- Requires snakepit ~> 0.7.5 (for PythonPackages support)

## [0.4.0] - 2025-12-25

### Added
- Compile-time pre-pass pipeline (scan -> introspect -> generate) with manifest + lockfile.
- Deterministic source output: one file per library under `lib/snakebridge_generated/*.ex`, committed to git.
- Snakepit-aligned runtime helpers (`snakebridge.call` / `snakebridge.stream`) and runtime client override for tests.
- Snakepit-backed Python execution for introspection and docs.
- Lockfile environment identity recorded from Snakepit runtime (version, platform, hash).
- Discovery metadata for classes and submodules, including deterministic regeneration.
- Example projects updated/added for v3 (`examples/math_demo`, `examples/proof_pipeline`).

### Changed
- Library configuration now lives in dependency options (`mix.exs`), not `config/*.exs`.
- Generated specs return `{:ok, term()} | {:error, Snakepit.Error.t()}` and use `Snakepit.PyRef`/`Snakepit.ZeroCopyRef`.
- Doc search now ranks results using discovery metadata.
- Runtime behavior is fully delegated to Snakepit; SnakeBridge stays compile-time only.

### Removed
- Legacy v2 mix tasks (`snakebridge.gen`, `list`, `info`, `clean`, `remove`) and registry-driven CLI flow.
- Multi-file adapter output under `lib/snakebridge/adapters/`.
- Auto-gitignore behavior for generated bindings.

## [0.3.2] - 2025-12-23

### Added
- Zero-friction Python integration with auto venv/pip
- Automated adapter creation with `mix snakebridge.adapter.create`

## [0.3.1] - 2025-12-23

### Changed
- Manifest as single source of truth
- Bridges relocated to `priv/python/bridges/`

## [0.3.0] - 2025-12-23

### Added
- Manifest-driven workflow with mix tasks
- Built-in manifests for sympy, pylatexenc, math-verify
- Snakepit auto-start launcher

## [0.2.0] - 2025-10-26

### Added
- Live Python integration with generic adapter
- Public API: discover, generate, integrate
- Mix tasks for discovery and generation

## [0.1.0] - 2025-10-25

### Added
- Initial release
- Core configuration schema
- Type system mapper
- Basic code generation

[0.7.2]: https://github.com/nshkrdotcom/snakebridge/compare/v0.7.1...v0.7.2
[0.7.1]: https://github.com/nshkrdotcom/snakebridge/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/nshkrdotcom/snakebridge/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/nshkrdotcom/snakebridge/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/nshkrdotcom/snakebridge/releases/tag/v0.1.0
