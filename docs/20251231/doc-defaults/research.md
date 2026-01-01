# DOC/DEFAULT MISMATCHES RESEARCH: MVP-CRITICAL ISSUE #4

**Investigation Date:** December 31, 2025
**Scope:** Audit of public API documentation vs implementation
**Status:** Multiple mismatches identified

## EXECUTIVE SUMMARY

Several documentation vs implementation mismatches exist in SnakeBridge:
- Ref TTL defaults are inconsistent across docs and code
- `set_attr/4` return type docs don't match actual returns
- Missing top-level convenience functions that are documented in examples

---

## 1. REF TTL DEFAULT DISCREPANCY

### 1.1 Documented Values

| Source | File | Line | Claimed Default |
|--------|------|------|-----------------|
| Module doc | `lib/snakebridge.ex` | 48 | "default TTL of 30 minutes" |
| Env var example | `lib/snakebridge.ex` | 128 | `SNAKEBRIDGE_REF_TTL_SECONDS \| 1800` |
| SessionContext doc | `lib/snakebridge/session_context.ex` | 40 | "default 30 minutes" |
| SessionContext option | `lib/snakebridge/session_context.ex` | 66 | `:ttl_seconds` default: 3600 (1 hour) |
| README.md | `README.md` | 178 | `SNAKEBRIDGE_REF_TTL_SECONDS` default `0` (disabled) |

### 1.2 Actual Implementation

**Python adapter** (`priv/python/snakebridge_adapter.py`, line 63):
```python
DEFAULT_REF_TTL_SECONDS = 0.0  # DISABLED by default
```

### 1.3 Analysis

There are THREE different "defaults" documented:
- **0 seconds** (disabled) - What Python actually does
- **1800 seconds** (30 min) - What some Elixir docs claim
- **3600 seconds** (1 hour) - What SessionContext struct uses

**Impact:** Users reading different parts of the documentation will have conflicting expectations about ref expiration behavior.

---

## 2. SET_ATTR RETURN TYPE MISMATCH

### 2.1 Documentation

**SnakeBridge module** (`lib/snakebridge.ex`, lines 367-369):
```elixir
@doc """
...
## Examples

    :ok = SnakeBridge.set_attr(point_ref, :x, 10)
"""
@spec set_attr(Ref.t(), atom() | String.t(), term(), keyword()) :: :ok | {:error, term()}
```

### 2.2 Actual Implementation

**Runtime.ex** (`lib/snakebridge/runtime.ex`, line 547):
```elixir
@spec set_attr(Ref.t() | StreamRef.t() | map(), atom() | String.t(), term(), keyword()) ::
        {:ok, term()} | {:error, Snakepit.Error.t()}
```

**Dynamic.ex** (`lib/snakebridge/dynamic.ex`, line 39):
```elixir
@spec set_attr(Ref.t() | map(), atom() | String.t(), term(), keyword()) ::
        {:ok, term()} | {:error, Snakepit.Error.t()}
```

### 2.3 Analysis

| Aspect | Documented | Actual |
|--------|-----------|--------|
| Success return | `:ok` | `{:ok, term()}` |
| Error return | `{:error, term()}` | `{:error, Snakepit.Error.t()}` |
| Pattern in example | `:ok = SnakeBridge.set_attr(...)` | Would crash on `{:ok, _}` |

**Impact:** Code examples in documentation will crash when run.

---

## 3. MISSING TOP-LEVEL CONVENIENCE FUNCTIONS

### 3.1 Functions Referenced in Docs but Not Exposed

**SnakeBridge module** (`lib/snakebridge.ex`, line 75) documents:
```elixir
SnakeBridge.release_ref(ref)
```

**But checking actual exports:**
```elixir
grep -n "defdelegate\|^  def " lib/snakebridge.ex | grep -E "(release_ref|release_session)"
# No results
```

### 3.2 Where Functions Actually Live

| Function | Documented Location | Actual Location |
|----------|-------------------|-----------------|
| `release_ref/1` | `SnakeBridge.release_ref(ref)` | `SnakeBridge.Runtime.release_ref/2` |
| `release_ref/2` | Not documented | `SnakeBridge.Runtime.release_ref/2` |
| `release_session/1` | Not documented | `SnakeBridge.Runtime.release_session/2` |
| `release_session/2` | Not documented | `SnakeBridge.Runtime.release_session/2` |

### 3.3 Analysis

Users reading the module documentation see `SnakeBridge.release_ref(ref)` but must actually call `SnakeBridge.Runtime.release_ref(ref)`.

**Impact:** Users must discover the `Runtime` module to perform cleanup operations.

---

## 4. SESSIONCONTEXT TTL DOCUMENTATION INCONSISTENCY

### 4.1 Module-Level Documentation

**File:** `lib/snakebridge/session_context.ex`, line 40
```elixir
@moduledoc """
...
By default, sessions have a TTL of 30 minutes...
"""
```

### 4.2 Option Documentation

**File:** `lib/snakebridge/session_context.ex`, line 66
```elixir
* `:ttl_seconds` - Session time-to-live in seconds (default: 3600)
```

### 4.3 Struct Default

**File:** `lib/snakebridge/session_context.ex`, line 78
```elixir
defstruct [
  ...
  ttl_seconds: 3600,  # 1 hour, not 30 minutes
  ...
]
```

### 4.4 Analysis

The module doc says "30 minutes" but the actual default is 3600 seconds (1 hour).

---

## 5. PUBLIC API AUDIT

### 5.1 SnakeBridge Module Exports

```elixir
# Delegated functions (from lib/snakebridge.ex)
defdelegate call(module_or_path, function, args \\ [], opts \\ []), to: Dynamic
defdelegate method(ref, function, args \\ [], opts \\ []), to: Dynamic
defdelegate get_attr(ref, attr, opts \\ []), to: Dynamic
defdelegate set_attr(ref, attr, value, opts \\ []), to: Dynamic
defdelegate stream(module_or_path, function, args \\ [], opts \\ []), to: Dynamic
defdelegate stream_collect(ref_or_result, opts \\ []), to: Dynamic

# Direct functions
def current_session_id()
def set_session_id(session_id)
def with_session(opts \\ [], fun)
def release_auto_session()
```

### 5.2 Missing Convenience Functions

| Function | Expected at Top Level | Notes |
|----------|----------------------|-------|
| `release_ref/1` | Yes | Common cleanup operation |
| `release_ref/2` | Yes | With options |
| `release_session/1` | Yes | Session cleanup |
| `release_session/2` | Yes | With options |
| `get_module_attr/3` | Maybe | Dynamic module attribute access |

---

## 6. RECOMMENDATIONS

### 6.1 TTL Documentation Fix

**Option A:** Change Python default to 1800 and update all docs to say "30 minutes"
**Option B:** Update all Elixir docs to say "disabled by default (0)" to match Python
**Option C:** (Recommended) Update docs to clearly state:
- Python registry TTL: disabled by default (env var to enable)
- Elixir session context TTL: 3600 seconds (for session lifecycle)

### 6.2 set_attr Return Type Fix

Update `lib/snakebridge.ex`:
```elixir
@doc """
...
## Examples

    {:ok, _} = SnakeBridge.set_attr(point_ref, :x, 10)
"""
@spec set_attr(Ref.t(), atom() | String.t(), term(), keyword()) ::
        {:ok, term()} | {:error, term()}
```

### 6.3 Add Missing Convenience Functions

Add to `lib/snakebridge.ex`:
```elixir
@doc """
Releases a Python object reference, freeing memory in the Python process.
"""
defdelegate release_ref(ref, opts \\ []), to: Runtime

@doc """
Releases all references associated with a session.
"""
defdelegate release_session(session_id, opts \\ []), to: Runtime
```

### 6.4 SessionContext TTL Fix

Update `lib/snakebridge/session_context.ex` line 40:
```elixir
By default, sessions have a TTL of 1 hour (3600 seconds)...
```

---

## FILES REQUIRING CHANGES

| File | Change |
|------|--------|
| `lib/snakebridge.ex` | Fix `set_attr` spec and example; add `release_ref`/`release_session` delegates |
| `lib/snakebridge/session_context.ex` | Fix TTL documentation (30min → 1 hour) |
| `README.md` | Clarify TTL defaults |
| `priv/python/snakebridge_adapter.py` | Consider changing default if 1800 is preferred |

---

**Document Generated:** 2025-12-31
