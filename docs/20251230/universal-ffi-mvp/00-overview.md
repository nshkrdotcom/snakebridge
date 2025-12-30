# Universal FFI MVP - Overview

**Document Version**: 1.0
**Target Version**: 0.8.4
**Date**: 2025-12-30

## Executive Summary

This document set specifies the Minimum Viable Product (MVP) changes required to transform SnakeBridge from a "generator-first" Python FFI into a **universal FFI** that works out-of-the-box across the broadest set of Python libraries without requiring compile-time code generation.

The existing architectural primitives (dynamic calls, refs, method/attr access, callbacks) are sound. The gaps are in:

1. **Public Runtime API Surface** - String module paths don't work as documented
2. **Session Scoping** - Default behavior causes ref collisions and memory leaks
3. **Wire/Type Correctness** - Common Python patterns break due to missing type support

## The Seven MVP Changes

| # | Change | Priority | Impact |
|---|--------|----------|--------|
| 1 | [String Module Paths](./01-string-module-paths.md) | Critical | Enables dynamic FFI without codegen |
| 2 | [Auto Session](./02-auto-session.md) | Critical | Prevents ref leaks and collisions |
| 3 | [Explicit Bytes](./03-explicit-bytes.md) | High | Unlocks crypto/binary/networking APIs |
| 4 | [Tagged Dict](./04-tagged-dict.md) | High | Supports non-string-key Python dicts |
| 5 | [Encoder Fallback](./05-encoder-fallback.md) | Medium | Fail-fast on unsupported types |
| 6 | [Python Ref Safety](./06-python-ref-safety.md) | High | Guarantees ref-wrapping for non-JSON |
| 7 | [Universal API Surface](./07-universal-api.md) | High | Clean, documented FFI entry points |

## Architecture Context

### Current Call Flow

```
User Code
    │
    ▼
SnakeBridge.Runtime.call/4
    │
    ├─► is_atom(module) → python_module_name(module) → uses @snakebridge attrs
    │
    └─► is_binary(module) → python_module_name("string") → returns "unknown" ❌
    │
    ▼
Types.Encoder.encode/1 → JSON-safe payload
    │
    ▼
Snakepit.execute("snakebridge.call", payload)
    │
    ▼
Python Adapter (snakebridge_adapter.py)
    │
    ├─► snakebridge_types.decode() → Python args
    │
    ├─► Execute Python function
    │
    └─► snakebridge_types.encode() → Result
        │
        ├─► JSON-safe → pass through
        │
        └─► Non-JSON → _make_ref() → ref wire format
    │
    ▼
Types.Decoder.decode/1 → Elixir value or SnakeBridge.Ref
```

### Target Call Flow (After MVP)

```
User Code
    │
    ▼
SnakeBridge.call("module_path", :function, args, opts)  ← NEW: String paths work
    │
    ▼
SnakeBridge.Runtime.call/4
    │
    ├─► is_atom(module) → existing codegen path
    │
    └─► is_binary(module) → delegate to call_dynamic ← FIXED
    │
    ▼
current_session_id/0
    │
    └─► SessionContext.current() || auto_session_for_process() ← NEW: Auto session
    │
    ▼
Types.Encoder.encode/1
    │
    ├─► SnakeBridge.Bytes → {:__type__ => "bytes", ...} ← NEW: Explicit bytes
    │
    ├─► Map with non-string keys → {:__type__ => "dict", ...} ← NEW: Tagged dict
    │
    └─► Unknown type → raise SerializationError ← NEW: Fail fast
    │
    ▼
Python Adapter
    │
    └─► encode_result() → always ref-wrap non-JSON-safe ← HARDENED
```

## Implementation Order

The changes must be implemented in a specific order due to dependencies:

```
Phase 1: Type System Foundation
├── 03-explicit-bytes.md     (no deps)
├── 04-tagged-dict.md        (no deps)
└── 05-encoder-fallback.md   (no deps)

Phase 2: Session Infrastructure
└── 02-auto-session.md       (no deps, but affects all calls)

Phase 3: API Surface
├── 01-string-module-paths.md (requires session to work properly)
└── 07-universal-api.md       (requires 01 to be complete)

Phase 4: Python Adapter Hardening
└── 06-python-ref-safety.md   (requires type changes to be in place)
```

## Success Criteria

After implementing all MVP changes:

1. **Dynamic FFI works OOTB**:
   ```elixir
   {:ok, result} = SnakeBridge.call("math", "sqrt", [16])
   # => {:ok, 4.0}
   ```

2. **Sessions are automatic and safe**:
   ```elixir
   # No SessionContext setup required
   {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])
   # ref is automatically scoped to this process
   ```

3. **Bytes are explicit**:
   ```elixir
   {:ok, hash} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])
   ```

4. **Non-string-key dicts work**:
   ```elixir
   {:ok, result} = SnakeBridge.call("some_lib", "fn", [%{1 => "one", 2 => "two"}])
   ```

5. **Type errors are explicit**:
   ```elixir
   # Raises SnakeBridge.SerializationError, not silent corruption
   SnakeBridge.call("lib", "fn", [#PID<0.123.0>])
   ```

6. **All Python objects are ref-safe**:
   ```elixir
   {:ok, ref} = SnakeBridge.call("numpy", "array", [[1,2,3]])
   # ref is always a SnakeBridge.Ref, never a lossy partial encoding
   ```

## Testing Strategy

Each change includes:

1. **Unit tests** for the specific module being modified
2. **Integration tests** demonstrating the use case
3. **Property-based tests** where applicable (especially for type encoding)
4. **Negative tests** ensuring errors are raised appropriately

All tests must pass with:
- `mix test`
- `mix dialyzer` (no errors)
- `mix credo --strict` (no issues)

## Backwards Compatibility

These changes are designed to be backwards compatible:

| Change | Compatibility |
|--------|---------------|
| String module paths | Additive - new functionality |
| Auto session | Transparent - existing explicit sessions still work |
| Explicit bytes | Additive - new `SnakeBridge.Bytes` struct |
| Tagged dict | Wire format change - Python adapter handles both |
| Encoder fallback | Breaking - but silent failures were bugs |
| Python ref safety | Tighter guarantees - no behavior change for correct code |
| Universal API | Additive - new public functions |

## File Change Summary

### Elixir Files to Modify

| File | Changes |
|------|---------|
| `lib/snakebridge.ex` | Add universal FFI functions, `bytes/1` |
| `lib/snakebridge/runtime.ex` | String module path handling, auto-session |
| `lib/snakebridge/types/encoder.ex` | Bytes struct, tagged dict, error fallback |
| `lib/snakebridge/types/decoder.ex` | Tagged dict decoding |
| `lib/snakebridge/session_context.ex` | Auto-session infrastructure |
| `lib/snakebridge/bytes.ex` | NEW: Bytes wrapper struct |
| `lib/snakebridge/serialization_error.ex` | NEW: Error type |

### Python Files to Modify

| File | Changes |
|------|---------|
| `priv/python/snakebridge_types.py` | Tagged dict encode/decode |
| `priv/python/snakebridge_adapter.py` | Hardened result encoding |

### Test Files to Add/Modify

| File | Purpose |
|------|---------|
| `test/snakebridge/bytes_test.exs` | NEW: Bytes struct tests |
| `test/snakebridge/types/encoder_test.exs` | Tagged dict, bytes, error tests |
| `test/snakebridge/types/decoder_test.exs` | Tagged dict decoding tests |
| `test/snakebridge/runtime_string_module_test.exs` | NEW: String path tests |
| `test/snakebridge/auto_session_test.exs` | NEW: Auto session tests |
| `test/snakebridge/universal_ffi_test.exs` | NEW: Integration tests |

## Document Index

1. [01-string-module-paths.md](./01-string-module-paths.md) - Make string module paths work
2. [02-auto-session.md](./02-auto-session.md) - Automatic session per BEAM process
3. [03-explicit-bytes.md](./03-explicit-bytes.md) - Explicit bytes wrapper
4. [04-tagged-dict.md](./04-tagged-dict.md) - Tagged dict for non-string keys
5. [05-encoder-fallback.md](./05-encoder-fallback.md) - Fail-fast encoder
6. [06-python-ref-safety.md](./06-python-ref-safety.md) - Airtight Python ref wrapping
7. [07-universal-api.md](./07-universal-api.md) - Public universal FFI surface

## Changelog Entry Template

For version 0.8.4, after implementing all changes:

```markdown
## [0.8.4] - 2025-12-XX

### Added
- Universal FFI: `SnakeBridge.call/4` now accepts string module paths for dynamic Python calls
- Universal FFI: `SnakeBridge.stream/5` accepts string module paths
- Universal FFI: `SnakeBridge.get/3` for module attributes with string paths
- `SnakeBridge.Bytes` struct for explicit binary data encoding
- `SnakeBridge.bytes/1` convenience function
- Auto-session: BEAM processes automatically get session IDs without explicit `with_session/1`
- Tagged dict wire format for maps with non-string keys
- `SnakeBridge.SerializationError` for unsupported type encoding

### Changed
- Encoder now raises `SerializationError` instead of silently calling `inspect/1` on unknown types
- Python adapter now unconditionally ref-wraps non-JSON-serializable return values
- Session ID is always included in wire payloads (auto-generated if not explicit)

### Fixed
- `SnakeBridge.call/4` with string module path now correctly delegates to dynamic call
- Maps with integer/tuple/atom keys now round-trip correctly via tagged dict format
- Memory leaks from refs in "default" session when not using explicit `SessionContext`
```
