# REF LIFECYCLE CONTRACT RESEARCH: MVP-CRITICAL ISSUE #2

**Investigation Date:** December 31, 2025
**Scope:** Complete ref lifecycle analysis (creation, storage, retrieval, release, expiry)
**Status:** Critical gaps identified

## EXECUTIVE SUMMARY

SnakeBridge uses a **session-scoped Python object reference (ref) registry** keyed by `{session_id}:{ref_id}`. The implementation has critical design issues around **missing error classification** and **contradictory TTL documentation**.

**Key Findings:**
1. **No "ref not found" first-class error** - Invalid refs raise `KeyError` that's not translated to Elixir
2. **TTL contradictions** - Docs claim 30min but code defaults to 0.0 (disabled)
3. **Session affinity defaults to hint** - Strict routing modes now exist, but hint mode can still fall back
4. **Registry is single-threaded Python dict** - No distributed session support
5. **Auto-session enabled** - Every Elixir process gets automatic session ID

---

## 1. REF STRUCTURE AND WIRE FORMAT

### 1.1 Elixir Ref Definition
**File:** `lib/snakebridge/ref.ex` (Lines 1-50)

```elixir
defstruct [
  :id,                    # UUID hex string, unique within session
  :session_id,            # Session identifier
  :python_module,         # Module where object originated
  :library,               # Top-level library
  :type_name,             # Optional: Python type name
  schema: @schema_version # Version 1
]
```

**Wire Format (JSON):**
```json
{
  "__type__": "ref",
  "__schema__": 1,
  "id": "a1b2c3d4e5f6...",
  "session_id": "auto_<0.123.0>_1735707045000",
  "python_module": "pandas",
  "library": "pandas",
  "type_name": "DataFrame"
}
```

---

## 2. REF LIFECYCLE: ELIXIR → PYTHON → BACK

### 2.1 Creation Pipeline

**Elixir Side:** `lib/snakebridge/runtime.ex` (Lines 752-990)
1. `SnakeBridge.Runtime.call/4` → encodes args with `Types.encode/1`
2. Builds payload with `base_payload/5`
3. **Always includes `session_id`** - resolved via `resolve_session_id/2`
4. Sends payload to Python via `runtime_client().execute()`
5. Result decoded with `Types.decode/1`

**Python Side:** `priv/python/snakebridge_adapter.py` (Lines 470-539)

```python
def encode_result(result: Any, session_id: str, python_module: str, library: str) -> Any:
    encoded = encode(result)

    # If needs ref (non-JSON-serializable)
    if isinstance(encoded, dict) and encoded.get("__needs_ref__"):
        return _make_ref(session_id, result, python_module, library)

    return encoded
```

**Ref Storage:**
```python
def _make_ref(session_id: str, obj: Any, python_module: str, library: str) -> dict:
    ref_id = uuid.uuid4().hex
    key = f"{session_id}:{ref_id}"
    _prune_registry()
    _store_ref(key, obj)

    return {
        "__type__": "ref",
        "__schema__": REF_SCHEMA_VERSION,
        "id": ref_id,
        "session_id": session_id,
        ...
    }
```

---

## 3. REF RESOLUTION AND RETRIEVAL

### 3.1 Method Calls on Refs

**Elixir:** `SnakeBridge.Runtime.call_method/4` (Lines 393-417)
```elixir
def call_method(ref, function, args \\ [], opts \\ []) do
  wire_ref = normalize_ref(ref)
  session_id = resolve_session_id(runtime_opts, wire_ref)
  payload = wire_ref
    |> base_payload_for_ref(function, encoded_args, encoded_kwargs, idempotent)
    |> Map.put("call_type", "method")
    |> Map.put("instance", wire_ref)
end
```

**Python Resolution:** `snakebridge_adapter.py` (Lines 607-623)
```python
def _resolve_ref(ref: dict, session_id: str) -> Any:
    with _registry_lock:
        _prune_registry()
        ref_id, ref_session = _extract_ref_identity(ref, session_id)
        key = f"{ref_session}:{ref_id}"

        if key not in _instance_registry:
            raise KeyError(f"Unknown SnakeBridge reference: {ref_id}")  # PROBLEM!

        entry = _instance_registry[key]
        if isinstance(entry, dict):
            _touch_entry(entry)
            return entry.get("obj")
        return entry
```

### 3.2 Error Handling: The Critical Gap

**No first-class "ref not found" error exists:**

1. **Python raises KeyError** (Line 617):
   ```python
   raise KeyError(f"Unknown SnakeBridge reference: {ref_id}")
   ```

2. **This becomes a generic Python exception** sent to Elixir, not classified

3. **Elixir error translator** (`lib/snakebridge/error_translator.ex`) has NO handling for ref lifecycle errors:
   - Recognizes: ShapeMismatchError, OutOfMemoryError, DtypeMismatchError
   - Missing: RefNotFoundError, SessionMismatchError, InvalidRefError

4. **Session mismatch is caught but poorly:**
   ```python
   def _extract_ref_identity(ref: dict, session_id: str) -> Tuple[str, str]:
       ref_session = ref.get("session_id") or session_id

       if ref_session and session_id and ref_session != session_id:
           raise ValueError("SnakeBridge reference session mismatch")
   ```
   - Raises ValueError (generic)
   - Not translated to Elixir as a structured error

---

## 4. TTL BEHAVIOR: DOCUMENTATION VS CODE

### 4.1 Conflicting Claims

| Source | Claimed Default |
|--------|-----------------|
| README.md (line 178) | `SNAKEBRIDGE_REF_TTL_SECONDS` default `0` (disabled) |
| lib/snakebridge.ex (line 128) | Shows `1800` as default |
| SessionContext docs (line 40) | "30 minutes" |
| SessionContext struct (line 66) | `:ttl_seconds` default: 3600 (1 hour) |
| **Python adapter (line 63)** | `DEFAULT_REF_TTL_SECONDS = 0.0` (DISABLED) |

### 4.2 Actual Python Implementation

**Default constant** (`snakebridge_adapter.py`, Line 63):
```python
DEFAULT_REF_TTL_SECONDS = 0.0  # DISABLED by default
```

**Pruning mechanism** (Lines 152-166):
```python
def _prune_registry() -> None:
    with _registry_lock:
        ttl_seconds, max_size = _registry_limits()
        now = time.time()

        # Time-based eviction (only if TTL > 0)
        if ttl_seconds and ttl_seconds > 0:
            for key, entry in list(_instance_registry.items()):
                if now - _entry_last_access(entry) > ttl_seconds:
                    del _instance_registry[key]

        # LRU eviction (if registry exceeds max_size)
        if max_size and max_size > 0 and len(_instance_registry) > max_size:
            # ... evict oldest entries
```

### 4.3 TTL Summary

| Aspect | Value | Notes |
|--------|-------|-------|
| Default TTL | 0.0 seconds | **Disabled** |
| Environment variable | `SNAKEBRIDGE_REF_TTL_SECONDS` | Optional override |
| Elixir Session TTL | 3600s (1 hour) | Default per session context |
| Max refs per registry | 10,000 | `SNAKEBRIDGE_REF_MAX` env var |
| Eviction strategy | LRU by last access | When max_size exceeded |

**Critical Issue:** With TTL=0 (default), refs **never expire**. Cleanup only via:
1. Explicit `release_ref()` call
2. `release_session()` on process death
3. LRU when max_size exceeded

---

## 5. SESSION AFFINITY AND AUTO-SESSION

### 5.1 Auto-Session Implementation

**Elixir side** (`lib/snakebridge/runtime.ex`, Lines 863-937):

```elixir
defp ensure_auto_session do
  case Process.get(@auto_session_key) do
    nil ->
      session_id = generate_auto_session_id()
      setup_auto_session(session_id)
      session_id
    session_id ->
      session_id
  end
end

defp generate_auto_session_id do
  pid_string = self() |> :erlang.pid_to_list() |> to_string()
  timestamp = System.system_time(:millisecond)
  "auto_#{pid_string}_#{timestamp}"
end
```

**Auto-session format:** `auto_<0.123.0>_1735707045000`

### 5.2 SessionManager Lifecycle

**Process monitoring** (`lib/snakebridge/session_manager.ex`):
- Monitors owner process
- On owner death: calls `release_session()` via Task
- Cleans up all refs for that session

---

## 6. REF RELEASE AND SESSION CLEANUP

### 6.1 Individual Ref Release

**Elixir API** (`lib/snakebridge/runtime.ex`, Lines 574-590):
```elixir
def release_ref(ref, opts \\ []) do
  wire_ref = normalize_ref(ref)
  session_id = resolve_session_id(runtime_opts, wire_ref)
  payload = protocol_payload()
    |> Map.put("ref", wire_ref)
    |> maybe_put_session_id(session_id)

  runtime_client().execute("snakebridge.release_ref", payload, runtime_opts)
end
```

**Python handler** (`snakebridge_adapter.py`, Lines 626-638):
```python
def _release_ref(ref: dict, session_id: str) -> bool:
    with _registry_lock:
        ref_id, ref_session = _extract_ref_identity(ref, session_id)
        key = f"{ref_session}:{ref_id}"

        if key in _instance_registry:
            del _instance_registry[key]
            return True
        return False
```

### 6.2 Session Release

Deletes all refs with matching session_id prefix from registry.

---

## 7. ERROR SCENARIOS AND HANDLING

### 7.1 Error Cases in Code

| Error | Python Exception | Elixir Translation |
|-------|------------------|-------------------|
| Invalid Ref Payload | ValueError | None (generic) |
| Missing Ref ID | ValueError | None (generic) |
| Session Mismatch | ValueError | None (generic) |
| Ref Not Found | KeyError | None (generic) |

### 7.2 Proposed First-Class Errors

```elixir
defmodule SnakeBridge.RefNotFoundError do
  defexception [:ref_id, :session_id, :message]
end

defmodule SnakeBridge.SessionMismatchError do
  defexception [:expected_session, :actual_session, :ref_id, :message]
end

defmodule SnakeBridge.InvalidRefError do
  defexception [:reason, :message]
end
```

---

## 8. TEST COVERAGE GAPS

**Existing test files:**
- `test/snakebridge/auto_ref_test.exs` - Basic ref decoding
- `test/snakebridge/auto_session_test.exs` - Auto-session generation
- `test/snakebridge/session_manager_test.exs` - Session lifecycle

**Missing test coverage:**
- Ref not found error handling
- Session mismatch detection
- TTL expiration scenarios
- Registry exhaustion (max_size)
- Concurrent session access
- Cross-process ref sharing edge cases

---

## RECOMMENDATIONS

### Critical Fixes Needed

1. **Create first-class ref errors:**
   - `SnakeBridge.RefNotFoundError`
   - `SnakeBridge.SessionMismatchError`
   - `SnakeBridge.InvalidRefError`

2. **Update error translator** to catch and classify ref-related ValueError/KeyError from Python

3. **Document TTL behavior accurately** - clarify that default is disabled, not 30 minutes

4. **Add session affinity validation** - strict affinity helps, but ref mismatch errors should still be explicit

5. **Implement ref lifecycle tests** covering error scenarios

---

## CODE REFERENCES SUMMARY

| Concept | File | Lines |
|---------|------|-------|
| Ref struct definition | `lib/snakebridge/ref.ex` | 1-50 |
| Ref creation (Python) | `priv/python/snakebridge_adapter.py` | 470-483 |
| Registry storage | `priv/python/snakebridge_adapter.py` | 49-58, 169-172 |
| Ref resolution | `priv/python/snakebridge_adapter.py` | 607-623 |
| Error on not found | `priv/python/snakebridge_adapter.py` | 617 |
| Error on mismatch | `priv/python/snakebridge_adapter.py` | 189 |
| Runtime call_method | `lib/snakebridge/runtime.ex` | 393-417 |
| Auto-session generation | `lib/snakebridge/runtime.ex` | 909-925 |
| SessionManager monitoring | `lib/snakebridge/session_manager.ex` | 88-175 |
| TTL constants | `priv/python/snakebridge_adapter.py` | 63-64 |

---

**Document Generated:** 2025-12-31
