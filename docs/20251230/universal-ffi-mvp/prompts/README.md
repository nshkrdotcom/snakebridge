# Universal FFI MVP Implementation Prompts

These prompts are designed to be run **sequentially** to implement the Universal FFI MVP for SnakeBridge v0.8.4.

## Prompt Order (Dependencies)

```
prompt-01-type-system.md      ← Run first (no dependencies)
        │
        ▼
prompt-02-auto-session.md     ← Depends on 01
        │
        ▼
prompt-03-api-surface.md      ← Depends on 01, 02
        │
        ▼
prompt-04-python-hardening.md ← Depends on 01, 02, 03
        │
        ▼
prompt-05-examples-update.md  ← Depends on 01, 02, 03, 04 (run AFTER all features complete)
```

## Prompt Summary

| # | Prompt | Implements | Est. Lines |
|---|--------|-----------|------------|
| 01 | `prompt-01-type-system.md` | Bytes struct, TaggedDict, SerializationError | ~180 Elixir, ~80 Python |
| 02 | `prompt-02-auto-session.md` | Auto-session per BEAM process | ~150 Elixir |
| 03 | `prompt-03-api-surface.md` | String module paths, Universal API | ~200 Elixir |
| 04 | `prompt-04-python-hardening.md` | Python adapter ref safety | ~200 Python |
| 05 | `prompt-05-examples-update.md` | Update/create examples for new features | ~400 Elixir |

## How to Use

1. Start a new Claude session
2. Provide the prompt file content as input
3. Let Claude implement the changes following TDD
4. Verify all checks pass before moving to the next prompt

## Verification After Each Prompt

Each prompt includes a verification checklist:

```bash
# Run tests
mix test

# Check types
mix dialyzer

# Check code quality
mix credo --strict

# Verify no warnings
mix compile --warnings-as-errors
```

All must pass before proceeding to the next prompt.

## What Each Prompt Covers

### Prompt 01: Type System Foundation
- Creates `SnakeBridge.Bytes` struct for explicit binary encoding
- Creates `SnakeBridge.SerializationError` for fail-fast type errors
- Updates encoder/decoder for tagged dict format (non-string keys)
- Updates Python `snakebridge_types.py` for tagged dict

### Prompt 02: Auto Session
- Implements automatic session creation per BEAM process
- Updates `SnakeBridge.Runtime.current_session_id/0`
- Adds session lifecycle management
- Ensures refs are isolated per process

### Prompt 03: API Surface
- Enables string module paths in `call/4`, `stream/5`, `get_module_attr/3`
- Adds universal FFI API to `SnakeBridge` module
- Adds bang variants (`call!`, `get!`, `method!`, `attr!`)
- Documents the universal FFI surface

### Prompt 04: Python Hardening
- Ensures all non-JSON values return refs
- Updates `encode()` to mark unencodable values
- Updates `encode_result()` to always ref-wrap non-serializable
- Adds JSON safety validation

### Prompt 05: Examples Update
- Updates `dynamic_dispatch_example` with new convenience APIs
- Updates `types_showcase` with Bytes and non-string key examples
- Updates `session_lifecycle_example` with auto-session demonstration
- Creates NEW `universal_ffi_example` comprehensive showcase

## Expected Outcome

After completing all prompts:

```elixir
# Universal FFI works OOTB
{:ok, result} = SnakeBridge.call("math", "sqrt", [16])

# Sessions are automatic
{:ok, ref} = SnakeBridge.call("pathlib", "Path", ["."])

# Bytes are explicit
{:ok, hash} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])

# Non-string keys work
{:ok, _} = SnakeBridge.call("fn", "process", [%{1 => "one"}])

# Unsupported types fail fast
SnakeBridge.call("fn", "process", [self()])  # Raises SerializationError

# All Python objects are ref-safe
{:ok, ref} = SnakeBridge.call("numpy", "array", [[1,2,3]])  # Always a ref
```

## Changelog

After all prompts complete, the 0.8.4 changelog entry should include:

### Added
- Universal FFI: `SnakeBridge.call/4` accepts string module paths
- Universal FFI: `SnakeBridge.stream/5` accepts string module paths
- Universal FFI: `SnakeBridge.get/3` for module attributes
- `SnakeBridge.Bytes` struct for explicit binary encoding
- `SnakeBridge.SerializationError` for unsupported types
- Auto-session per BEAM process
- Tagged dict wire format for non-string keys
- Bang variants for universal FFI functions

### Changed
- Encoder raises `SerializationError` instead of `inspect/1` fallback
- Python adapter unconditionally ref-wraps non-JSON values
- Session ID always included in wire payloads

### Fixed
- Maps with integer/tuple keys serialize correctly
- Memory leaks from "default" session refs
- Ref collisions between processes
