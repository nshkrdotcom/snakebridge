- [x] Align wire schema + atom handling + protocol versioning
- [x] Manifest normalization + strict verification + dotted module fixes
- [x] Telemetry emission + async error handling + helper write-if-changed + Mix manifests
- [x] Type mapping + optional/variadic args + class type specs
- [x] Ref lifecycle + error translation policy + adapter updates
- [x] Tests, docs, version bump, changelog

# Foundational FFI Upgrades Plan (2025-12-29)

## Goals
- Lock a single wire schema across Elixir/Python, including atoms, bytes, and collections.
- Version the runtime payload contract and enforce compatibility.
- Make generation trustworthy (manifest keys, strict verification, dotted modules).
- Emit missing telemetry events and harden concurrency error handling.
- Use structured type info to generate real specs and more ergonomic wrappers.
- Add explicit ref lifecycle operations with predictable ref schemas.
- Provide configurable error translation for runtime calls.

## Approach
1. **Wire schema + atoms + protocol versions**
   - Unify encoder/decoder layouts (`elements`, `data`, `special_float`).
   - Add schema version marker + tolerant decode for legacy keys.
   - Add atom tagging with allowlist decode in Elixir.
   - Add protocol version to runtime payloads + Python enforcement.
   - Update tests and docs.

2. **Manifest + strict verification + dotted modules**
   - Normalize manifest symbol keys, migrate legacy keys on load.
   - Expand strict verification with AST-based checks for classes/methods/attrs.
   - Fix dotted Python library handling in generator/submodules and runtime.
   - Add/adjust tests.

3. **Telemetry + async error handling + Mix manifest support**
   - Emit scan/introspect/generate/docs/lock telemetry at source.
   - Handle Task.async_stream errors in Scanner/Introspector.
   - Return manifest/lock paths from Mix compiler.
   - Update helper generation to write-if-changed.
   - Add telemetry tests.

4. **Type mapping + wrapper ergonomics**
   - Extend inline introspection to return structured types.
   - Generate specs using TypeMapper and add class type alias.
   - Add optional/variadic positional arg wrappers (no `__args__` escape hatch).
   - Update generator tests and docs.

5. **Ref lifecycle + error translation policy**
   - Define ref schema + Elixir typespecs.
   - Add release_ref/release_session runtime functions.
   - Add TTL/LRU eviction in Python adapter.
   - Introduce error_mode (:raw/:translated/:raise_translated) and tests.

6. **Docs + versioning**
   - Update README + other docs as needed.
   - Bump version in mix.exs/README.
   - Update CHANGELOG for 2025-12-29.
