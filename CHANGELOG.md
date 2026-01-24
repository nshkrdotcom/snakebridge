# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.14.0] - 2026-01-23

### Added
- **Public API filtering** (`public_api: true`): New option for submodule introspection that filters to only modules with explicit public APIs
  - Modules with `__all__` defined are included
  - Modules with classes/functions defined in the module (not imported) are included
  - Private modules (any path component starting with `_`) are excluded
- **Compilation progress output**: Progress messages during introspection and generation phases
- **Method collision fix**: When a Python class has both `__init__` and a method named `new`, the method is renamed to `python_new` to avoid arity collisions
- **Session cleanup failure telemetry**: Emits `[:snakebridge, :session, :cleanup, :error]` when best-effort cleanup fails

### Changed
- Registry is now supervised at runtime while keeping lazy startup for compile-time tasks

## [0.13.0] - 2026-01-21

### Added
- Generated class wrappers now include `@moduledoc` from Python class docstrings
- Generated constructors now include `@doc` from `__init__` method docstrings
- Generated methods now include `@doc` from method docstrings
- Documentation is automatically converted from Python formats (Google, NumPy, Sphinx, Epytext) to ExDoc Markdown

### Added
- Sanitizes docstring Markdown links that escape the docs root (e.g. `../...`) to avoid ExDoc missing-file warnings

## [0.12.0] - 2026-01-20

### Added
- **Split layout generation mode**: New `generated_layout: :split` config option (now default) produces Python-shaped directory structure with `__init__.ex` files for package modules.
  - Mirrors Python module paths: `dspy.predict` → `dspy/predict/__init__.ex`
  - Class modules get separate files: `Dspy.Predict.RLM` → `dspy/predict/rlm.ex`
  - Registry tracks all generated files for split layout
- **`Generator.PathMapper` module**: New path mapping utilities for Python-to-Elixir file path conversion.
- **`Generator.render_module_file/7`**: Renders individual module files for split layout.
- **`Generator.render_class_file/4`**: Renders standalone class module files.
- **`Class.render_class_standalone/3`**: Renders classes as top-level modules for split layout.

### Changed
- **Default layout is now `:split`**: Generated wrappers use Python-shaped directory structure by default.
- Legacy single-file layout (`:single`) remains available via `config :snakebridge, generated_layout: :single`.
- Registry entries now contain relative file paths from `generated_dir` for split layout.

## [0.11.0] - 2026-01-19

### Fixed
- SnakeBridge compiler now short-circuits when bindings are already up to date (manifest/lock/generated files).
- Suppressed the compile-time "preparing bindings" banner and the extra compile hint by default.
- Examples now enable Snakepit's Python dependency auto-install to prevent missing gRPC/protobuf imports when running stdlib-only demos.

## [0.10.0] - 2026-01-19

### Added
- **Max coverage signature pipeline**: Tiered signature sources (runtime, text_signature, runtime_hints, stubs, stubgen, variadic) with per-symbol `signature_source` metadata.
- **Doc source tiers**: Runtime docs first, stub docs next, module doc fallback, with per-symbol `doc_source` metadata.
- **Stub resolution upgrades**: Local `.pyi`, `types-<pkg>` packages, optional typeshed, and overload metadata handling.
- **Stubgen fallback with caching** for libraries without stubs.
- **Strict signature thresholds** (`strict_signatures`, `min_signature_tier`) with per-library overrides.
- **Coverage reports** (JSON + Markdown) with tier counts and structured issues.
- **New examples**: `coverage_report_example`, `stub_fallback_example`, and updated `strict_mode_example`.

### Changed
- Manifest schema now records signature/doc sources, missing reasons, and overload counts.
- Introspection issues are captured in coverage reports instead of emitting warnings during builds.

### Fixed
- Class/module collisions are now disambiguated (with `Class` suffixes) and stale class entries are pruned to prevent duplicate module definitions.
- Lowercase/invalid class module segments no longer produce invalid typespec aliases; segments are camelized and invalid aliases fall back to `term()`.
- Attribute accessors now avoid name collisions with methods by appending `_attr` when needed.
- Leading-underscore parameter names are normalized to avoid unused-variable warnings in generated wrappers.
- Prefer the Snakepit-managed venv (default: `priv/snakepit/python/venv`) when resolving the Python runtime in `ConfigHelper` to avoid environment mismatches.

### Documentation
- README and Generated Wrappers guide now document max coverage configuration and signature tiers.
- Revamped README.md for clarity and conciseness with focused quick start.
- Added Configuration Reference and Coverage Reports guides.
- Improved HexDocs menu structure with organized module groups.

## [0.9.0] - 2026-01-11

### Added
- **Graceful serialization for containers**: When a Python result is a container
  (list, dict, tuple, set, frozenset) that contains non-serializable objects,
  SnakeBridge now preserves the container structure and ref-wraps ONLY the
  non-serializable leaf objects. This is a significant improvement over the
  previous behavior where any non-serializable item caused the entire container
  to become a single ref.

  Example - DSPy history with non-serializable `response` field:
  ```elixir
  {:ok, history} = SnakeBridge.call("dspy_module", "get_history", [])

  # history is a list of maps - NOT a single opaque ref!
  for entry <- history do
    # Serializable fields are directly accessible
    IO.puts("Model: #{entry["model"]}, cost: #{entry["cost"]}")

    # Only the non-serializable field becomes a ref
    response = entry["response"]
    {:ok, id} = SnakeBridge.attr(response, "id")
  end
  ```

- **Cycle detection in serialization**: Self-referential structures (e.g., a list
  containing itself) are now handled safely - cycles are detected and converted to
  refs to prevent infinite recursion.

- **Enhanced ref metadata**: Ref payloads now include `type_name` and `__type_name__`
  fields containing the Python class name, enabling better inspection and debugging.

- **Serialization helpers**: `SnakeBridge.unserializable?/1` and
  `SnakeBridge.unserializable_info/1` to detect and inspect non-JSON-serializable
  Python objects that were replaced with markers (Snakepit markers, not refs)
  - Delegates to `Snakepit.Serialization` for consistent behavior
  - Markers include type information; repr is opt-in via environment variables
  - See Snakepit's graceful serialization guide for full documentation

- **Comprehensive documentation guides**: Added 10 in-depth guides covering all
  major SnakeBridge features including Getting Started, Universal FFI, Generated
  Wrappers, Refs and Sessions, Type System, Streaming, Error Handling, Telemetry,
  Best Practices, and Session Affinity. Available in `guides/` and integrated into
  HexDocs with organized navigation.

- **Python test suite for adapter**: New comprehensive Python tests for
  `encode_result` behavior in `test_snakebridge_adapter.py`, covering nested refs,
  cycle detection, and type metadata.

- **Integration tests for graceful serialization**: New Elixir tests verifying
  validation config structures, nested refs, and ref usability. Test helpers use
  real Python stdlib (`re.compile()` patterns) instead of mocks.

- **Graceful serialization demo in universal_ffi_example**: Section 9 demonstrates
  mixing compiled regex patterns with serializable metadata, showing direct field
  access while patterns remain as usable refs.

- **Atom round-trip preservation**: When `SNAKEBRIDGE_ATOM_CLASS=true`, Python `Atom`
  objects returned from functions now encode as tagged atoms (`{"__type__": "atom", ...}`)
  rather than becoming refs, preserving the expected round-trip semantics.

### Changed
- **Container serialization behavior (breaking)**: Non-serializable items inside
  containers no longer force the whole container into a ref. Instead, only the
  leaf values that cannot be serialized become refs. This is the new default and
  only behavior - no feature flag or opt-out.

  Before:
  ```python
  # Python returns: [{"model": "gpt-4", "response": <ModelResponse>}]
  # Elixir received: %SnakeBridge.Ref{}  # The entire list was wrapped!
  ```

  After:
  ```python
  # Python returns: [{"model": "gpt-4", "response": <ModelResponse>}]
  # Elixir receives: [%{"model" => "gpt-4", "response" => %SnakeBridge.Ref{}}]
  ```

- **Explicit arity generation for optional positional parameters**: Functions with
  optional positional parameters now generate multiple explicit arities instead of
  using the variadic args list pattern. This provides better compile-time checking
  and clearer generated code.

- **Class module names are properly camelized**: Class modules like `numpy.ndarray`
  are now generated as `Numpy.Ndarray` instead of `Numpy.ndarray`, following Elixir
  naming conventions.

- **Attribute name sanitization**: Class attributes with special characters (e.g.,
  `T`, `mT`) are now sanitized to valid Elixir identifiers (`t`, `m_t`).

- **OTP logger level alignment**: `ConfigHelper.configure_snakepit!/1` now aligns
  the OTP logger level with the Elixir logger level to suppress low-level SSL and
  public_key logs.

- **Examples enable numpy by default**: The `signature_showcase` and
  `class_resolution_example` examples now include numpy without requiring the
  `SNAKEBRIDGE_EXAMPLE_NUMPY=1` environment variable.

### Fixed
- Suppress ssl/public_key CA loading logs instead of tls_certificate_check logs
  during application startup.

### Internal
- **Schema version alignment**: Tagged values (bytes, datetime, tuple, set, dict, etc.)
  now use `SCHEMA_VERSION`; refs and stream_refs use `REF_SCHEMA_VERSION`. This prevents
  future breakage if the constants diverge.
- **Async generator exclusion centralized**: `_is_generator_or_iterator` and `_is_streamable`
  now explicitly exclude async generators (they cannot be consumed via `next()`).
- **Broad exception fallback**: `encode_result` catches any `Exception` during encoding
  and falls back to ref-wrapping, preventing hard failures from concurrent mutation,
  weird `__iter__` implementations, or deeply nested structures.
- **Memoization for refs/stream_refs**: `ref_memo` dict tracks created refs to ensure
  the same object yields the same ref id (deduplication).
- **Container snapshotting**: List, dict, set, and frozenset iteration now snapshots
  the container first to reduce "changed size during iteration" errors.
- **`_is_json_safe` recursion guard**: The safety-net validation is wrapped in
  `try/except RecursionError` to prevent crashes on near-limit structures.
- **Fallback ref cleanup**: On encoding failure, any refs created during partial encoding
  are removed from the registry to prevent unreachable ref leakage.

## [0.8.2] - 2026-01-11

### Added
- **Pool name propagation for refs**: Refs now retain the originating `pool_name` when provided via `__runtime__: [pool_name: :my_pool]`
  - `SnakeBridge.Ref` and `SnakeBridge.StreamRef` structs include a `pool_name` field
  - Subsequent `get_attr`, `call_method`, `set_attr`, and stream operations automatically reuse the same pool
  - Eliminates the need to pass `pool_name` on every ref operation
- **`generate: :all` mode**: New library configuration option to generate wrappers for ALL public symbols in a Python module, not just those detected in your code
  - Use `{:dspy, "2.6.5", generate: :all}` to generate complete bindings
  - Supports `submodules` option for recursive module introspection
  - Full module introspection via `Introspector.introspect_module/2`
- **Context-aware type mapping**: `TypeMapper` now builds context from discovered classes and resolves type references to generated Elixir modules
  - `TypeMapper.build_context/1` creates a mapping of Python classes to Elixir modules
  - `TypeMapper.with_context/2` runs code with type resolution context
  - `TypeMapper.to_spec/2` resolves class types when context is available
- **Parsed docstring support**: `Generator.normalize_docstring/1` handles both raw strings and parsed docstring maps from full module introspection
- **Multi-session example**: New `examples/multi_session_example` demonstrating concurrent isolated Python sessions - "multiple snakes in the pit"
  - Concurrent sessions with `Task.async` and different session IDs
  - State isolation between sessions
  - Parallel processing pattern with `Task.async_stream`
  - Session-scoped object lifetime management
- **Multi-session documentation**: README now includes "Multiple Snakes in the Pit" section explaining concurrent session patterns for multi-tenant apps, A/B testing, and parallel workers
- **Affinity modes in examples**: `multi_session_example` now demonstrates hint vs strict queue vs strict fail-fast under load, per-call overrides, tainted worker handling, and streaming with session-bound refs
- **Affinity defaults example**: New `examples/affinity_defaults_example` for single-pool defaults and per-call overrides
- **Session affinity guide**: Added `guides/SESSION_AFFINITY.md` with routing semantics, errors, and streaming guidance
- **ConfigHelper affinity support**: `SnakeBridge.ConfigHelper` accepts `affinity` and `pools` to configure Snakepit routing defaults per pool

### Changed
- **Class methods now skip `self`/`cls` parameters**: Generated method signatures no longer include implicit Python instance/class parameters
- **Method deduplication**: When introspection finds multiple signatures for the same method (e.g., `__getitem__` and `get` mapping to the same Elixir name), only one is generated
- **Reserved word handling**: Parameter names that are Elixir reserved words (e.g., `and`, `or`, `not`) are now prefixed with `py_` (e.g., `py_and`)
- **Variadic args signature**: Functions with both `*args` and `opts` no longer have conflicting defaults
- **Session cleanup logging is opt-in**: Set `config :snakebridge, session_cleanup_log_level: :debug` to log cleanup events; cleanup also emits `[:snakebridge, :session, :cleanup]` telemetry

### Removed
- **Hardcoded ML type mappings**: Removed special-case handling for `numpy.ndarray`, `torch.Tensor`, `pandas.DataFrame`, etc. These now use the generic class type system with context-aware resolution

### Fixed
- `Inspect` and `String.Chars` protocol implementations for `SnakeBridge.Ref` now catch `:exit` errors in addition to exceptions, preventing crashes during ref inspection when the runtime is unavailable

### Internal
- Refactored `RealPythonCase` test support for cleaner Python dependency resolution
- Added test coverage for `generate: :all`, context-aware type mapping, and self/cls parameter skipping
- Added test coverage for pool_name propagation on ref operations
- Bridge client example now dynamically resolves gRPC address via Snakepit's `await_ready/1` with fallback to `SNAKEPIT_GRPC_ADDRESS`/`SNAKEPIT_GRPC_ADDR` env vars
- Python bridge client demo prefers `SNAKEPIT_GRPC_ADDRESS` over deprecated `SNAKEPIT_GRPC_ADDR`
- Test helper auto-generates unique `instance_name` and `instance_token` for test isolation with parallel partition support

## [0.8.1] - 2026-01-09

### Changed
- Dev and test logger configs no longer pin `:console` as the only backend.
- Example lockfiles now record Elixir 1.19.4.

### Internal
- Prefer direct list emptiness checks in generator, registry, and tests.
- Reuse a shared streaming chunk callback for clarity.
- Updated tooling/lockfile deps (supertester 0.5.1, credo 1.7.15, dialyxir 1.4.7, ex_doc 0.39.3, erlex 0.2.8).

## [0.8.0] - 2026-01-02

### Added
- `SnakeBridge.run_as_script/2` wrapper with safe defaults for Snakepit 0.9.0 exit semantics.
- Script shutdown telemetry forwarder for `[:snakepit, :script, :shutdown, ...]` events.
- Integration tests covering script exit behavior and embedded usage.

### Changed
- Examples now use `SnakeBridge.run_as_script/2` instead of calling Snakepit directly.
- Docs updated to describe `exit_mode`/`stop_mode` defaults and `SNAKEPIT_SCRIPT_EXIT`.

### Fixed
- Clarified script shutdown behavior to avoid unintended VM stops in embedded usage.
- Examples runner now starts applications during `mix run` so session tracking is available.

### Internal
- Added `supertester` 0.4.0 for robust test infrastructure.
- Refactored flaky `Process.sleep` calls to use polling-based `eventually/2` helper.
- Test files now use proper process monitoring and message passing for synchronization.
- Split runtime responsibilities into Runtime.Payload, Runtime.SessionResolver, and Runtime.Streamer.
- Extracted compiler flow into Compiler.Pipeline and Compiler.IntrospectionRunner; Mix task now delegates.
- Split generator rendering into Generator.Function and Generator.Class with the Generator module coordinating output.

## [0.7.10] - 2026-01-01

### Changed
- **auto_install default changed from `:dev` to `:dev_test`** - Python packages now auto-install during both `mix compile` and `mix test`, eliminating the need to run `mix snakebridge.setup` before running tests
- Added `:dev_test` option for `auto_install` setting (matches both dev and test environments)
- Environment variable `SNAKEBRIDGE_AUTO_INSTALL` now also accepts `dev_test` value
- Updated all examples to use the new default

### Fixed
- First-run test experience - `mix test` now works out of the box without requiring `mix snakebridge.setup` first

## [0.7.9] - 2026-01-01

### Added
- **ConfigHelper**: New `SnakeBridge.ConfigHelper` module for zero-boilerplate snakepit configuration
- Add `configure_snakepit!/1` for runtime auto-configuration of Python venv, adapter, and PYTHONPATH
- Add `snakepit_config/1` for declarative config generation
- Add `debug_config/0` for troubleshooting venv detection

### Changed
- All examples now use simplified `config/runtime.exs` with ConfigHelper (replaces ~30 lines of boilerplate)
- Updated README installation instructions to include runtime.exs setup
- ConfigHelper automatically follows symlinks to find venv in path dependencies

### Fixed
- External projects using snakebridge as a dependency no longer need manual snakepit configuration
- Venv detection now works correctly for path deps, hex deps, and local development

## [0.7.8] - 2026-01-01

### Changed
- **Breaking**: Python library configuration now uses `python_deps` project key instead of dependency tuple options
- This fixes the "unknown options: :libraries" error when installing from Hex
- Configuration now mirrors how `deps/0` works with a parallel `python_deps/0` function
- `generated_dir` and `metadata_dir` now read from Application config instead of dependency options

### Migration

Before (broken with Hex packages):
```elixir
def deps do
  [{:snakebridge, "~> 0.7.7", libraries: [...]}]  # ERROR with Hex!
end
```

After (works with all installation methods):
```elixir
def project do
  [
    app: :my_app,
    deps: deps(),
    python_deps: python_deps()
  ]
end

defp deps do
  [{:snakebridge, "~> 0.7.8"}]
end

defp python_deps do
  [
    {:numpy, "1.26.0"},
    {:pandas, "2.0.0", include: ["DataFrame", "read_csv"]}
  ]
end
```

## [0.7.7] - 2025-12-31

### Added
- `SnakeBridge.Defaults` module centralizing all configurable values with documentation
- Full configuration support for previously hardcoded values:
  - `:introspector_timeout` - Introspection timeout in ms (default: 30,000)
  - `:introspector_max_concurrency` - Max concurrent introspection tasks (default: `System.schedulers_online()`)
  - `:pytorch_index_base_url` - PyTorch wheel index URL for private mirrors (default: `"https://download.pytorch.org/whl/"`)
  - `:cuda_thresholds` - CUDA version to variant mapping, extensible for new CUDA versions
  - `:session_max_refs` - Maximum refs per session (default: 10,000)
  - `:session_ttl_seconds` - Session TTL in seconds (default: 3,600)

### Changed
- Introspector now supports both nested (`:introspector`) and flat key configuration for backwards compatibility
- CUDA variant fallback logic now uses configurable thresholds instead of hardcoded guards
- Session context defaults now read from application config, overridable per-call
- **Runtime timeout architecture overhaul** - fixes the 30s gRPC deadline problem that broke LLM calls:
  - New default timeout: 120s (2 minutes) instead of 30s
  - New default stream timeout: 30 minutes instead of 5 minutes
  - Profile-based timeout system with built-in profiles: `:default`, `:streaming`, `:ml_inference`, `:batch_job`
  - Per-library profile mapping via `runtime: [library_profiles: %{"transformers" => :ml_inference}]`
  - All runtime calls now apply timeout defaults via `apply_runtime_defaults/3`
  - `__runtime__` is now a documented first-class feature (not an undocumented passthrough)
  - Generated module docs now include Runtime Options section explaining timeout configuration

### Runtime Timeout Architecture

The new timeout system addresses the "30s gRPC deadline kills LLM calls" problem by:

1. **Raising default timeout** from 30s to 120s (2 minutes)
2. **Profile-based configuration** - select `:ml_inference` for 10-minute timeout, `:batch_job` for infinity
3. **Per-call override** via `__runtime__: [timeout: X]` or `__runtime__: [timeout_profile: :ml_inference]`
4. **Library-specific defaults** - configure `transformers` to always use `:ml_inference` profile
5. **Streaming-aware** - streaming calls default to `:streaming` profile with 30-minute stream_timeout

Example configuration:
```elixir
config :snakebridge,
  runtime: [
    timeout_profile: :default,
    library_profiles: %{
      "transformers" => :ml_inference,
      "torch" => :batch_job
    }
  ]
```

Example per-call override:
```elixir
Transformers.generate(prompt, __runtime__: [timeout_profile: :ml_inference])
Numpy.compute(data, __runtime__: [timeout: 600_000])
```

## [0.7.6] - 2025-12-31

### Added
- First-class ref lifecycle errors: `RefNotFoundError`, `SessionMismatchError`, `InvalidRefError`
- Error translator now converts Python ref errors to structured Elixir exceptions
- Introspection failures now logged with details during normal mode compilation
- Telemetry event `[:snakebridge, :introspection, :error]` emitted for introspection failures
- Introspection summary displayed after compilation if errors occurred
- `SnakeBridge.release_ref/1,2` delegates for explicit ref cleanup
- `SnakeBridge.release_session/1,2` delegates for session cleanup

### Fixed
- `set_attr` @spec and documentation now correctly show `{:ok, term()}` return type
- TTL documentation now consistently states: disabled by default (env var), SessionContext default 3600s
- Introspection errors no longer silently swallowed in normal mode compilation
- Users now see which symbols failed to introspect and why
- Session ID consistency across all Runtime call paths - `__runtime__: [session_id: X]` now respected by:
  - `call/4` with atom modules
  - `get_module_attr/3` with both atom and string modules
  - `call_class/4`
  - `call_helper/3` (both list and map opts variants)
  - `call_method/4` (runtime opts now override ref's embedded session)
  - `stream/5` with atom modules
- All call paths now use `resolve_session_id()` for consistent priority: runtime_opts > ref > context > auto-session

### Removed
- Pre-populated `priv/snakebridge/registry.json` files from repository; registry is now generated per-project during `mix compile`

### Changed
- Added `priv/snakebridge/registry.json` to `.gitignore` to prevent tracking of generated registry artifacts
- Release validation against Snakepit 0.8.7 with passing Elixir/Python test suites and dialyzer

## [0.7.5] - 2025-12-30

### Added
- Python BridgeClient for gRPC execution with streaming support
- Streaming client decoding for ToolChunk payloads (JSON + raw bytes) with metadata and chunk ids
- Correlation ID propagation via `x-snakepit-correlation-id` metadata header
- Any encoding compatibility for tool parameters (raw JSON bytes)
- Streaming client tests covering RPC selection, headers, decoding, and binary parameter validation
- `bridge_client_example` demonstrating Python BridgeClient usage against the Elixir BridgeServer

### Changed
- README streaming documentation clarifies server-side streaming RPC usage and `supports_streaming` requirement

### Fixed
- Ensure session affinity is always passed to Snakepit pool for ref-based operations
- Preserve boolean results in Python gRPC response type inference
- Stream iteration now prefers `__iter__` before falling back to `__next__`

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

[0.14.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.8.3...v0.9.0
[0.8.3]: https://github.com/nshkrdotcom/snakebridge/compare/v0.8.2...v0.8.3
[0.8.2]: https://github.com/nshkrdotcom/snakebridge/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/nshkrdotcom/snakebridge/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/nshkrdotcom/snakebridge/compare/v0.7.10...v0.8.0
[0.7.10]: https://github.com/nshkrdotcom/snakebridge/compare/v0.7.9...v0.7.10
[0.7.9]: https://github.com/nshkrdotcom/snakebridge/compare/v0.7.8...v0.7.9
[0.7.8]: https://github.com/nshkrdotcom/snakebridge/compare/v0.7.7...v0.7.8
[0.7.7]: https://github.com/nshkrdotcom/snakebridge/compare/v0.7.6...v0.7.7
[0.7.6]: https://github.com/nshkrdotcom/snakebridge/compare/v0.7.5...v0.7.6
[0.7.5]: https://github.com/nshkrdotcom/snakebridge/compare/v0.7.4...v0.7.5
[0.7.4]: https://github.com/nshkrdotcom/snakebridge/compare/v0.7.3...v0.7.4
[0.7.3]: https://github.com/nshkrdotcom/snakebridge/compare/v0.7.2...v0.7.3
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
