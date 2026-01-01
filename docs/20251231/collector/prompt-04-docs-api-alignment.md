# PROMPT 4: Documentation and API Alignment

**Version Target:** SnakeBridge v0.8.7
**Prompt Number:** 4 of 4
**Dependencies:** Prompts 2 and 3 must be completed first

---

## REQUIRED READING

Before implementing this prompt, read the following files in their entirety:

1. **`lib/snakebridge.ex`** - Main module with public API delegates and documentation
2. **`lib/snakebridge/runtime.ex`** - Runtime implementation with actual function signatures
3. **`lib/snakebridge/session_context.ex`** - Session context with TTL documentation
4. **`README.md`** - User-facing documentation

---

## CONTEXT

This prompt fixes documentation vs implementation mismatches discovered in the MVP audit. These issues cause user confusion and runtime crashes when following documented examples.

### Issue DD-1: `set_attr` Return Type Mismatch

**Location:** `lib/snakebridge.ex` lines 354-371

**Documentation claims:**
```elixir
@doc """
...
## Examples

    {:ok, obj} = SnakeBridge.call("some_module", "SomeClass", [])
    :ok = SnakeBridge.set_attr(obj, "property", "new_value")
"""
@spec set_attr(Ref.t(), atom() | String.t(), term(), keyword()) ::
        :ok | {:error, term()}
```

**Actual implementation in `lib/snakebridge/runtime.ex` line 547:**
```elixir
@spec set_attr(SnakeBridge.Ref.t(), atom() | String.t(), term(), opts()) ::
        {:ok, term()} | {:error, Snakepit.Error.t()}
```

**Impact:** Code examples like `:ok = SnakeBridge.set_attr(...)` will crash with a match error because the actual return is `{:ok, term()}`.

### Issue DD-2: Missing Top-Level Convenience Delegates

**Location:** `lib/snakebridge.ex` - module documentation (line 75) references:
```elixir
SnakeBridge.release_ref(ref)  # Explicit cleanup
```

But `release_ref/1,2` and `release_session/1,2` are NOT delegated from `SnakeBridge`. Users must call `SnakeBridge.Runtime.release_ref/2` directly, contradicting the documented API.

**Functions that exist in Runtime but not exposed at top level:**
- `release_ref/1` and `release_ref/2`
- `release_session/1` and `release_session/2`

### Issue DD-3: TTL Documentation Inconsistencies

Three different TTL defaults are documented across the codebase:

| Location | Claimed Default |
|----------|-----------------|
| `lib/snakebridge.ex` line 48 | "30 minutes" |
| `lib/snakebridge.ex` line 128 | `SNAKEBRIDGE_REF_TTL_SECONDS \| 1800` |
| `lib/snakebridge/session_context.ex` line 40 | "30 minutes" |
| `lib/snakebridge/session_context.ex` line 66 | `ttl_seconds` default: 3600 (1 hour) |
| `lib/snakebridge/session_context.ex` line 79 | struct default: 3600 |
| `README.md` line 178 | `SNAKEBRIDGE_REF_TTL_SECONDS` default `0` (disabled) |

**Actual defaults:**
- Python adapter: `DEFAULT_REF_TTL_SECONDS = 0.0` (disabled by default)
- Elixir SessionContext struct: `ttl_seconds: 3600` (1 hour)

---

## GOAL

Fix all documentation/implementation mismatches to ensure:

1. `set_attr` documentation and @spec match the actual `{:ok, term()}` return type
2. `release_ref/1,2` and `release_session/1,2` are accessible via `SnakeBridge.release_ref/1,2` and `SnakeBridge.release_session/1,2`
3. TTL documentation is consistent and accurate across all files
4. All new delegates have tests verifying they work correctly

### Success Criteria

- [ ] `set_attr` @spec shows `{:ok, term()}` success return
- [ ] `set_attr` example shows `{:ok, _} = SnakeBridge.set_attr(...)`
- [ ] `SnakeBridge.release_ref/1` and `SnakeBridge.release_ref/2` exist and delegate to Runtime
- [ ] `SnakeBridge.release_session/1` and `SnakeBridge.release_session/2` exist and delegate to Runtime
- [ ] TTL documentation states: disabled by default (env var), SessionContext uses 3600s
- [ ] New test file verifies delegate behavior
- [ ] All existing tests pass
- [ ] `mix dialyzer` passes
- [ ] `mix credo --strict` passes
- [ ] CHANGELOG.md updated

---

## IMPLEMENTATION STEPS

### Step 1: Write Tests First (TDD)

Create `test/snakebridge/api_delegates_test.exs`:

```elixir
defmodule SnakeBridge.ApiDelegatesTest do
  use ExUnit.Case, async: true

  describe "release_ref/1,2 delegates" do
    test "release_ref/1 is accessible from SnakeBridge module" do
      assert function_exported?(SnakeBridge, :release_ref, 1)
    end

    test "release_ref/2 is accessible from SnakeBridge module" do
      assert function_exported?(SnakeBridge, :release_ref, 2)
    end
  end

  describe "release_session/1,2 delegates" do
    test "release_session/1 is accessible from SnakeBridge module" do
      assert function_exported?(SnakeBridge, :release_session, 1)
    end

    test "release_session/2 is accessible from SnakeBridge module" do
      assert function_exported?(SnakeBridge, :release_session, 2)
    end
  end
end
```

Run `mix test test/snakebridge/api_delegates_test.exs` - tests should FAIL initially.

### Step 2: Fix `set_attr` Documentation and @spec

In `lib/snakebridge.ex`, update the `set_attr` documentation and @spec (around lines 354-371):

**Before:**
```elixir
@doc """
Set an attribute on a Python object reference.

## Parameters

- `ref` - A `SnakeBridge.Ref` from a previous call
- `attr` - Attribute name as atom or string
- `value` - New value for the attribute
- `opts` - Runtime options

## Examples

    {:ok, obj} = SnakeBridge.call("some_module", "SomeClass", [])
    :ok = SnakeBridge.set_attr(obj, "property", "new_value")
"""
@spec set_attr(Ref.t(), atom() | String.t(), term(), keyword()) ::
        :ok | {:error, term()}
defdelegate set_attr(ref, attr, value, opts \\ []), to: Dynamic
```

**After:**
```elixir
@doc """
Set an attribute on a Python object reference.

## Parameters

- `ref` - A `SnakeBridge.Ref` from a previous call
- `attr` - Attribute name as atom or string
- `value` - New value for the attribute
- `opts` - Runtime options

## Examples

    {:ok, obj} = SnakeBridge.call("some_module", "SomeClass", [])
    {:ok, _} = SnakeBridge.set_attr(obj, "property", "new_value")
"""
@spec set_attr(Ref.t(), atom() | String.t(), term(), keyword()) ::
        {:ok, term()} | {:error, term()}
defdelegate set_attr(ref, attr, value, opts \\ []), to: Dynamic
```

### Step 3: Add Missing Delegates

In `lib/snakebridge.ex`, add the following delegates after the existing `release_auto_session/0` delegate (around line 452):

```elixir
@doc """
Releases a Python object reference, freeing memory in the Python process.

Call this to explicitly release a ref when you're done with it, rather than
waiting for session cleanup or process termination.

## Parameters

- `ref` - A `SnakeBridge.Ref` to release
- `opts` - Runtime options (optional)

## Examples

    {:ok, ref} = SnakeBridge.call("pathlib", "Path", ["/tmp"])
    # ... use ref ...
    :ok = SnakeBridge.release_ref(ref)

## Notes

- After release, the ref is invalid and should not be used
- Releasing an already-released ref is a no-op
- For bulk cleanup, use `release_session/1` instead
"""
@spec release_ref(Ref.t(), keyword()) :: :ok | {:error, term()}
defdelegate release_ref(ref, opts \\ []), to: Runtime

@doc """
Releases all Python object references associated with a session.

Use this for bulk cleanup of all refs in a session, rather than releasing
them individually.

## Parameters

- `session_id` - The session ID to release
- `opts` - Runtime options (optional)

## Examples

    session_id = SnakeBridge.current_session()
    # ... create many refs ...
    :ok = SnakeBridge.release_session(session_id)

## Notes

- After release, all refs from that session are invalid
- The session can still be reused for new calls
- For auto-sessions, prefer `release_auto_session/0`
"""
@spec release_session(String.t(), keyword()) :: :ok | {:error, term()}
defdelegate release_session(session_id, opts \\ []), to: Runtime
```

### Step 4: Fix TTL Documentation in `lib/snakebridge.ex`

Update the module documentation (around line 48) to be accurate:

**Before:**
```elixir
5. **Ref TTL**: Python refs have a default TTL of 30 minutes. Refs not accessed
   within this window may be cleaned up. Touch refs by using them to reset TTL.
```

**After:**
```elixir
5. **Ref TTL**: Python ref TTL is disabled by default. Enable via
   `SNAKEBRIDGE_REF_TTL_SECONDS` environment variable. When enabled, refs
   not accessed within the TTL window are cleaned up automatically.
```

Update the environment variable table (around line 128):

**Before:**
```elixir
| `SNAKEBRIDGE_REF_TTL_SECONDS` | `1800` | Ref TTL (0 to disable) |
```

**After:**
```elixir
| `SNAKEBRIDGE_REF_TTL_SECONDS` | `0` | Ref TTL in seconds (0 = disabled) |
```

### Step 5: Fix TTL Documentation in `lib/snakebridge/session_context.ex`

Update the module documentation (around line 40):

**Before:**
```elixir
- Refs exceed TTL (default 30 minutes) or max count (default 10,000)
```

**After:**
```elixir
- Refs exceed TTL (SessionContext default: 1 hour) or max count (default 10,000)
```

Update the option documentation (around line 66) to clarify the default:

**Before:**
```elixir
- `:ttl_seconds` - Ref time-to-live (default: 3600)
```

**After:**
```elixir
- `:ttl_seconds` - Session time-to-live in seconds (default: 3600, i.e., 1 hour)
```

### Step 6: Fix README.md TTL Documentation (if needed)

The README (line 178) correctly states default is `0` (disabled). Verify this is accurate and consistent.

### Step 7: Run Tests

```bash
# Run the new delegate tests
mix test test/snakebridge/api_delegates_test.exs

# Run all tests
mix test

# Run dialyzer
mix dialyzer

# Run credo
mix credo --strict
```

### Step 8: Update CHANGELOG.md

Add entries under `[Unreleased]` or create `[0.8.7]` section:

```markdown
## [0.8.7] - 2025-12-31

### Added
- `SnakeBridge.release_ref/1,2` delegates for explicit ref cleanup
- `SnakeBridge.release_session/1,2` delegates for session cleanup

### Fixed
- `set_attr` @spec and documentation now correctly show `{:ok, term()}` return type
- TTL documentation now consistently states: disabled by default (env var), SessionContext default 3600s
```

---

## FILES TO MODIFY

| File | Changes |
|------|---------|
| `lib/snakebridge.ex` | Fix `set_attr` @spec and example; add `release_ref/1,2` and `release_session/1,2` delegates; fix TTL docs |
| `lib/snakebridge/session_context.ex` | Fix TTL documentation (30min -> 1 hour) |
| `test/snakebridge/api_delegates_test.exs` | NEW FILE: tests for new delegates |
| `CHANGELOG.md` | Add v0.8.7 entries |

---

## VERIFICATION

After completing all steps, verify:

1. **Tests pass:**
   ```bash
   mix test
   ```

2. **Dialyzer passes:**
   ```bash
   mix dialyzer
   ```

3. **Credo passes:**
   ```bash
   mix credo --strict
   ```

4. **New delegates work:**
   ```elixir
   # In iex -S mix
   function_exported?(SnakeBridge, :release_ref, 1)   # => true
   function_exported?(SnakeBridge, :release_ref, 2)   # => true
   function_exported?(SnakeBridge, :release_session, 1)   # => true
   function_exported?(SnakeBridge, :release_session, 2)   # => true
   ```

5. **Documentation is correct:**
   ```bash
   mix docs
   # Open doc/SnakeBridge.html and verify:
   # - set_attr shows {:ok, term()} return
   # - release_ref and release_session are documented
   # - TTL documentation is consistent
   ```

---

## NOTE

**This prompt depends on Prompts 2 and 3 being completed first.**

- Prompt 2 fixes session consistency issues in `lib/snakebridge/runtime.ex`
- Prompt 3 adds ref lifecycle error types and introspection visibility

The documentation fixes in this prompt should align with any API changes made in those prompts. If Prompts 2 or 3 modified any public API signatures or behaviors, ensure this prompt's documentation reflects those changes.

---

## COMMIT MESSAGE

When committing, use:

```
fix(docs): align API documentation with implementation

- Fix set_attr @spec to return {:ok, term()} instead of :ok
- Add release_ref/1,2 and release_session/1,2 top-level delegates
- Fix TTL documentation: disabled by default, SessionContext uses 3600s
- Add tests for new delegate functions

Closes DD-1, DD-2, DD-3 from MVP audit.
```
