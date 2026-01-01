# SESSION ID CONSISTENCY RESEARCH: MVP-CRITICAL ISSUE #1

**Investigation Date:** December 31, 2025
**Scope:** Complete session_id flow analysis across all call paths
**Status:** Documented inconsistencies identified

## EXECUTIVE SUMMARY

Session ID consistency is **BROKEN** across multiple call paths in SnakeBridge. The core issue:

- **Payload session_id** is set via `base_payload/5` using `current_session_id()` at payload construction time
- **Runtime routing session_id** is passed via `__runtime__: [session_id: ...]` options at execution time
- **Python adapter stores/resolves refs** under the payload session_id
- **Snakepit routing** may route under a different session_id from runtime_opts

This creates **three distinct session IDs** that can be different:
1. Payload's embedded session_id (source: `current_session_id()`)
2. Runtime opts session_id (source: `__runtime__` option)
3. Ref's embedded session_id (source: ref struct)

## DETAILED FINDINGS

### 1. SESSION ID COMPUTATION POINTS

#### Point A: `current_session_id()` (lib/snakebridge/runtime.ex:856-861)
```elixir
defp current_session_id do
  case SnakeBridge.SessionContext.current() do
    %{session_id: session_id} when is_binary(session_id) -> session_id
    _ -> ensure_auto_session()
  end
end
```

**Purpose:** Gets session_id from context OR creates auto-session
**Called by:** `base_payload/5`, `helper_payload/5`, module attr calls
**Problem:** Uses process context, NOT aware of `__runtime__` overrides

#### Point B: `resolve_session_id()` (lib/snakebridge/runtime.ex:704-708)
```elixir
def resolve_session_id(runtime_opts, ref \\ nil) do
  session_id_from_runtime_opts(runtime_opts) ||
    session_id_from_ref(ref) ||
    current_session_id()
end
```

**Priority:** runtime_opts > ref.session_id > context session > auto-session
**Called by:** Dynamic calls, ref operations (method, attr, set_attr, release_ref)
**Problem:** Different functions use different strategies

---

### 2. CALL PATH ANALYSIS

#### PATH 1: Module Atom Calls (Generated Wrappers)
**Entry Point:** `SnakeBridge.Runtime.call(atom_module, function, args, opts)`
**Lines:** 56-70

```elixir
def call(module, function, args, opts) when is_atom(module) do
  {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
  encoded_args = encode_args(args ++ extra_args)
  encoded_kwargs = encode_kwargs(kwargs)
  payload = base_payload(module, function, encoded_args, encoded_kwargs, idempotent)
  session_id = Map.get(payload, "session_id")  # Gets from payload
  runtime_opts = ensure_session_opt(runtime_opts, session_id)
  metadata = call_metadata(payload, module, function, "function")
  execute_with_telemetry(metadata, fn ->
    runtime_client().execute("snakebridge.call", payload, runtime_opts)
  end)
end
```

**Session ID Source:**
1. `base_payload()` calls `maybe_put_session_id(current_session_id())`
2. Session_id extracted from built payload
3. Passed to `ensure_session_opt()` to fill runtime_opts

**Problem:** If `__runtime__: [session_id: X]` is passed, it's IGNORED because:
- `base_payload()` uses `current_session_id()`
- Extracted session_id is used for runtime_opts
- Payload's session_id already set and sent

**Inconsistency:** `__runtime__` session override has NO EFFECT for atom modules

---

#### PATH 2: String Module Dynamic Calls
**Entry Point:** `SnakeBridge.Runtime.call_dynamic(module_path_string, function, args, opts)`
**Lines:** 80-114

```elixir
def call_dynamic(module_path, function, args \\ [], opts \\ []) when is_binary(module_path) do
  {args, opts} = normalize_args_opts(args, opts)
  {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
  encoded_args = encode_args(args ++ extra_args)
  encoded_kwargs = encode_kwargs(kwargs)

  # Determine session_id ONCE - this is the single source of truth
  session_id = resolve_session_id(runtime_opts)  # Uses resolve_session_id

  payload =
    protocol_payload()
    |> Map.put("call_type", "dynamic")
    |> Map.put("module_path", module_path)
    |> Map.put("function", to_string(function))
    |> Map.put("args", encoded_args)
    |> Map.put("kwargs", encoded_kwargs)
    |> Map.put("idempotent", idempotent)
    |> maybe_put_session_id(session_id)  # Only if not nil

  runtime_opts = ensure_session_opt(runtime_opts, session_id)

  execute_with_telemetry(metadata, fn ->
    runtime_client().execute("snakebridge.call", payload, runtime_opts)
  end)
end
```

**Session ID Source:**
1. Uses `resolve_session_id(runtime_opts)` with priority order
2. Puts same session_id in payload
3. Passes to runtime_opts

**Correct:** Respects `__runtime__: [session_id: X]` override
**Problem:** Only for dynamic calls, NOT for atom module calls

---

#### PATH 3: Method/Attribute Calls on Refs
**Entry Point:** `SnakeBridge.Runtime.call_method(ref, function, args, opts)`
**Lines:** 395-417

Uses `resolve_session_id(runtime_opts, wire_ref)` - **Correct pattern**

---

#### PATH 4: Module Attribute Reads (Atom Modules)
**Entry Point:** `SnakeBridge.Runtime.get_module_attr(module_atom, attr, opts)`
**Lines:** 470-489

Uses `base_payload()` then extracts - **Same problem as PATH 1**

---

#### PATH 5: Module Attribute Reads (String Modules)
**Entry Point:** `SnakeBridge.Runtime.get_module_attr(module_string, attr, opts)`
**Lines:** 440-467

Uses `current_session_id()` directly - **Ignores `__runtime__` override**

---

#### PATH 6: Ref Operations (get_attr, set_attr, release_ref)
**Lines:** 500-590

All use `resolve_session_id(runtime_opts, wire_ref)` - **Correct pattern**

---

### 3. INCONSISTENCY MATRIX

| Call Type | Payload Session | Runtime Opts Session | Respects `__runtime__` |
|-----------|-----------------|----------------------|----------------------|
| Module Atom `call/4` | `current_session_id()` | `ensure_session_opt()` | NO |
| Dynamic `call_dynamic/4` | `resolve_session_id()` | `ensure_session_opt()` | YES |
| Module Attr Atom | `current_session_id()` | `ensure_session_opt()` | NO |
| Module Attr String | `current_session_id()` | `ensure_session_opt()` | NO |
| Class Call | `current_session_id()` | `ensure_session_opt()` | NO |
| Method Call | `resolve_session_id()` with ref | `ensure_session_opt()` | YES |
| Get Attr | `resolve_session_id()` with ref | `ensure_session_opt()` | YES |
| Set Attr | `resolve_session_id()` with ref | `ensure_session_opt()` | YES |
| Helper Call | `current_session_id()` | `ensure_session_opt()` | NO |
| Stream | `current_session_id()` | `ensure_session_opt()` | NO |
| Stream Next | `resolve_session_id()` | `ensure_session_opt()` | YES |
| Release Ref | `resolve_session_id()` | `ensure_session_opt()` | YES |

---

### 4. PYTHON ADAPTER SESSION ID USAGE

**File:** `priv/python/snakebridge_adapter.py`

Adapter prioritizes payload session_id over context:
```python
session_id = None
if isinstance(arguments, dict) and arguments.get("session_id"):
    session_id = arguments.get("session_id")              # Payload wins
elif context is not None and hasattr(context, "session_id"):
    session_id = context.session_id
elif self.session_context is not None:
    session_id = self.session_context.session_id
else:
    session_id = "default"
```

---

## RECOMMENDATIONS FOR FIX

### Option 1: Always Use `resolve_session_id()` (Recommended)

Replace all `current_session_id()` with `resolve_session_id(runtime_opts)`:

```elixir
# BEFORE
def call(module, function, args, opts) when is_atom(module) do
  {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
  payload = base_payload(module, function, encoded_args, encoded_kwargs, idempotent)
  session_id = Map.get(payload, "session_id")
  ...
end

# AFTER
def call(module, function, args, opts) when is_atom(module) do
  {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
  session_id = resolve_session_id(runtime_opts)  # Check runtime opts first
  payload =
    base_payload(module, function, encoded_args, encoded_kwargs, idempotent)
    |> Map.put("session_id", session_id)
  ...
end
```

**Affected Functions:**
- `call/4` (atom)
- `get_module_attr/3` (atom)
- `get_module_attr/3` (string)
- `call_class/4`
- `call_helper/3` (both variants)
- `stream/5` (atom)
- `build_dynamic_payload/4`

---

## FILES REQUIRING CHANGES

1. **lib/snakebridge/runtime.ex** (PRIMARY)
   - All functions listed above

2. **test/snakebridge/end_to_end_test.exs** (TESTING)
   - Expand session consistency tests
   - Test both atom and string paths with `__runtime__` override

3. **priv/python/snakebridge_adapter.py** (VALIDATION)
   - Consider stricter validation that payload and context session_ids match

---

## TESTING STRATEGY

Comprehensive test suite should verify:

1. **Auto-session isolation:** Each process gets its own session
2. **Explicit session override:** `SessionContext.with_session()` overrides auto-session
3. **Runtime session override:** `__runtime__: [session_id: X]` affects payload
4. **Ref session consistency:** Refs carry correct session_id to Python
5. **Cross-path consistency:** Atom and string paths behave identically
6. **Session mismatch detection:** Python rejects cross-session refs
7. **No session leakage:** Refs created in one session not accessible in another

---

**Document Generated:** 2025-12-31
**Thoroughness Level:** COMPLETE - All 12 call paths analyzed
