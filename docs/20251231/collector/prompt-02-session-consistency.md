# PROMPT 02: Session ID Consistency Fix

**Target Version:** SnakeBridge v0.8.7
**Issue IDs:** SC-1, SC-2
**Severity:** Critical
**Estimated Time:** 45-60 minutes

---

## REQUIRED READING

Before implementing, you MUST read these files completely:

1. **`lib/snakebridge/runtime.ex`** - The primary file to modify
   - Pay special attention to lines 56-70 (`call/4` atom module path)
   - Lines 440-467 (`get_module_attr/3` string module path)
   - Lines 470-489 (`get_module_attr/3` atom module path)
   - Lines 369-391 (`call_class/4`)
   - Lines 116-148 (`call_helper/3` both variants)
   - Lines 196-216 (`stream/5` atom module path)
   - Lines 704-708 (`resolve_session_id/2` - the correct pattern)
   - Lines 856-861 (`current_session_id/0` - the problematic pattern)

2. **`lib/snakebridge/session_context.ex`** - Understand session context behavior

3. **`test/snakebridge/auto_session_test.exs`** - Reference for test patterns with Mox
4. **`test/snakebridge/runtime_contract_test.exs`** - Reference for payload testing
5. **`test/snakebridge/session_context_test.exs`** - Reference for session context testing

---

## CONTEXT

### The Problem

Session ID consistency is **BROKEN** across multiple call paths in SnakeBridge. The core issue:

- **Payload session_id** is set via `base_payload/5` using `current_session_id()` at payload construction time
- **Runtime routing session_id** is passed via `__runtime__: [session_id: ...]` options at execution time
- **Python adapter stores/resolves refs** under the payload session_id
- **Snakepit routing** may route under a different session_id from runtime_opts

This creates **three distinct session IDs** that can be different:
1. Payload's embedded session_id (source: `current_session_id()`)
2. Runtime opts session_id (source: `__runtime__` option)
3. Ref's embedded session_id (source: ref struct)

### Which Call Paths Are Broken

| Call Type | Current Session Source | Respects `__runtime__` | Status |
|-----------|------------------------|------------------------|--------|
| `call/4` (atom module) | `current_session_id()` via `base_payload` | **NO** | BROKEN |
| `call_dynamic/4` (string module) | `resolve_session_id()` | YES | Correct |
| `get_module_attr/3` (atom) | `current_session_id()` via `base_payload` | **NO** | BROKEN |
| `get_module_attr/3` (string) | `current_session_id()` directly | **NO** | BROKEN |
| `call_class/4` | `current_session_id()` via `base_payload` | **NO** | BROKEN |
| `call_method/4` | `resolve_session_id()` with ref | YES | Correct |
| `get_attr/3` | `resolve_session_id()` with ref | YES | Correct |
| `set_attr/4` | `resolve_session_id()` with ref | YES | Correct |
| `call_helper/3` (map opts) | `current_session_id()` via `helper_payload` | **NO** | BROKEN |
| `call_helper/3` (list opts) | `current_session_id()` via `helper_payload` | **NO** | BROKEN |
| `stream/5` (atom module) | `current_session_id()` via `base_payload` | **NO** | BROKEN |
| `stream_next/2` | `resolve_session_id()` | YES | Correct |
| `release_ref/2` | `resolve_session_id()` | YES | Correct |

### Why `resolve_session_id()` Is Correct

The `resolve_session_id/2` function (lines 704-708) implements the correct priority:

```elixir
def resolve_session_id(runtime_opts, ref \\ nil) do
  session_id_from_runtime_opts(runtime_opts) ||  # 1. Explicit runtime override
    session_id_from_ref(ref) ||                   # 2. Ref's embedded session
    current_session_id()                          # 3. Context/auto-session
end
```

This ensures that when a user passes `__runtime__: [session_id: "custom"]`, that session is used for:
1. The payload's `session_id` field (sent to Python)
2. The runtime_opts for Snakepit routing
3. All downstream operations

---

## GOAL

Fix all broken call paths to use `resolve_session_id(runtime_opts)` consistently.

### Success Criteria

1. All 12 call paths respect `__runtime__: [session_id: X]` override
2. New comprehensive test file validates all call paths
3. Existing tests continue to pass
4. No breaking changes to the public API
5. CHANGELOG updated for v0.8.7

---

## IMPLEMENTATION STEPS

### Step 1: Create Test File First (TDD)

Create `test/snakebridge/session_consistency_test.exs`:

```elixir
defmodule SnakeBridge.SessionConsistencyTest do
  @moduledoc """
  Tests session ID consistency across all Runtime call paths.

  These tests verify that the `__runtime__: [session_id: X]` option
  is respected by ALL call paths, ensuring payload session_id and
  routing session_id are always consistent.
  """

  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  # Test module for atom module paths
  defmodule TestMathModule do
    def __snakebridge_python_name__, do: "math"
    def __snakebridge_library__, do: "math"
  end

  defmodule TestClassModule do
    def __snakebridge_python_name__, do: "sympy"
    def __snakebridge_library__, do: "sympy"
    def __snakebridge_python_class__, do: "Symbol"
  end

  setup do
    original = Application.get_env(:snakebridge, :runtime_client)
    Application.put_env(:snakebridge, :runtime_client, SnakeBridge.RuntimeClientMock)

    # Clear any existing session context
    SnakeBridge.Runtime.clear_auto_session()
    SnakeBridge.SessionContext.clear_current()

    on_exit(fn ->
      if original do
        Application.put_env(:snakebridge, :runtime_client, original)
      else
        Application.delete_env(:snakebridge, :runtime_client)
      end
    end)

    :ok
  end

  @custom_session "custom_override_session_123"

  describe "call/4 atom module respects __runtime__ session override" do
    test "payload and runtime_opts use the overridden session_id" do
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        # Payload must contain the overridden session_id
        assert payload["session_id"] == @custom_session
        # Runtime opts must also have the session_id
        assert Keyword.get(opts, :session_id) == @custom_session
        {:ok, 2.0}
      end)

      {:ok, _} =
        SnakeBridge.Runtime.call(
          TestMathModule,
          :sqrt,
          [4],
          __runtime__: [session_id: @custom_session]
        )
    end

    test "without override, uses context session" do
      context_session = "context_session_456"

      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert payload["session_id"] == context_session
        assert Keyword.get(opts, :session_id) == context_session
        {:ok, 2.0}
      end)

      SnakeBridge.SessionContext.with_session([session_id: context_session], fn ->
        {:ok, _} = SnakeBridge.Runtime.call(TestMathModule, :sqrt, [4])
      end)
    end
  end

  describe "call_dynamic/4 respects __runtime__ session override" do
    test "payload and runtime_opts use the overridden session_id" do
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert payload["session_id"] == @custom_session
        assert Keyword.get(opts, :session_id) == @custom_session
        {:ok, 2.0}
      end)

      {:ok, _} =
        SnakeBridge.Runtime.call_dynamic(
          "math",
          "sqrt",
          [4],
          __runtime__: [session_id: @custom_session]
        )
    end
  end

  describe "get_module_attr/3 string module respects __runtime__ session override" do
    test "payload and runtime_opts use the overridden session_id" do
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert payload["session_id"] == @custom_session
        assert Keyword.get(opts, :session_id) == @custom_session
        {:ok, 3.14159}
      end)

      {:ok, _} =
        SnakeBridge.Runtime.get_module_attr(
          "math",
          "pi",
          __runtime__: [session_id: @custom_session]
        )
    end
  end

  describe "get_module_attr/3 atom module respects __runtime__ session override" do
    test "payload and runtime_opts use the overridden session_id" do
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert payload["session_id"] == @custom_session
        assert Keyword.get(opts, :session_id) == @custom_session
        {:ok, 3.14159}
      end)

      {:ok, _} =
        SnakeBridge.Runtime.get_module_attr(
          TestMathModule,
          :pi,
          __runtime__: [session_id: @custom_session]
        )
    end
  end

  describe "call_class/4 respects __runtime__ session override" do
    test "payload and runtime_opts use the overridden session_id" do
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert payload["session_id"] == @custom_session
        assert Keyword.get(opts, :session_id) == @custom_session
        {:ok, %{"__type__" => "ref", "id" => "ref-1"}}
      end)

      {:ok, _} =
        SnakeBridge.Runtime.call_class(
          TestClassModule,
          :__init__,
          ["x"],
          __runtime__: [session_id: @custom_session]
        )
    end
  end

  describe "call_helper/3 with list opts respects __runtime__ session override" do
    test "payload and runtime_opts use the overridden session_id" do
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert payload["session_id"] == @custom_session
        assert Keyword.get(opts, :session_id) == @custom_session
        {:ok, %{"installed" => true}}
      end)

      {:ok, _} =
        SnakeBridge.Runtime.call_helper(
          "snakebridge.ping",
          [],
          __runtime__: [session_id: @custom_session]
        )
    end
  end

  describe "call_helper/3 with map opts uses context session" do
    # Map opts variant cannot have __runtime__, uses context only
    test "uses context session when in SessionContext" do
      context_session = "helper_context_session"

      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, _opts ->
        assert payload["session_id"] == context_session
        {:ok, %{"installed" => true}}
      end)

      SnakeBridge.SessionContext.with_session([session_id: context_session], fn ->
        {:ok, _} = SnakeBridge.Runtime.call_helper("snakebridge.ping", [], %{})
      end)
    end
  end

  describe "stream/5 atom module respects __runtime__ session override" do
    test "payload and runtime_opts use the overridden session_id" do
      expect(SnakeBridge.RuntimeClientMock, :execute_stream, fn "snakebridge.stream",
                                                                 payload,
                                                                 _callback,
                                                                 opts ->
        assert payload["session_id"] == @custom_session
        assert Keyword.get(opts, :session_id) == @custom_session
        :ok
      end)

      :ok =
        SnakeBridge.Runtime.stream(
          TestMathModule,
          :iter,
          [10],
          [__runtime__: [session_id: @custom_session]],
          fn _item -> :ok end
        )
    end
  end

  describe "call_method/4 respects __runtime__ session override over ref session" do
    test "runtime override takes precedence over ref's embedded session" do
      ref =
        SnakeBridge.Ref.from_wire_format(%{
          "__type__" => "ref",
          "__schema__" => 1,
          "id" => "ref-1",
          "session_id" => "ref_embedded_session",
          "python_module" => "test",
          "library" => "test"
        })

      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        # Runtime override takes precedence
        assert payload["session_id"] == @custom_session
        assert Keyword.get(opts, :session_id) == @custom_session
        {:ok, "result"}
      end)

      {:ok, _} =
        SnakeBridge.Runtime.call_method(
          ref,
          :some_method,
          [],
          __runtime__: [session_id: @custom_session]
        )
    end

    test "without override, uses ref's embedded session" do
      ref_session = "ref_embedded_session"

      ref =
        SnakeBridge.Ref.from_wire_format(%{
          "__type__" => "ref",
          "__schema__" => 1,
          "id" => "ref-1",
          "session_id" => ref_session,
          "python_module" => "test",
          "library" => "test"
        })

      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert payload["session_id"] == ref_session
        assert Keyword.get(opts, :session_id) == ref_session
        {:ok, "result"}
      end)

      {:ok, _} = SnakeBridge.Runtime.call_method(ref, :some_method, [])
    end
  end

  describe "session override priority" do
    test "runtime_opts > ref > context > auto-session" do
      ref_session = "ref_session"
      context_session = "context_session"

      ref =
        SnakeBridge.Ref.from_wire_format(%{
          "__type__" => "ref",
          "__schema__" => 1,
          "id" => "ref-1",
          "session_id" => ref_session,
          "python_module" => "test",
          "library" => "test"
        })

      # Test 1: Runtime opts override everything
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert payload["session_id"] == @custom_session
        assert Keyword.get(opts, :session_id) == @custom_session
        {:ok, "result"}
      end)

      SnakeBridge.SessionContext.with_session([session_id: context_session], fn ->
        {:ok, _} =
          SnakeBridge.Runtime.call_method(
            ref,
            :method,
            [],
            __runtime__: [session_id: @custom_session]
          )
      end)

      # Test 2: Ref session overrides context (when no runtime opts)
      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, opts ->
        assert payload["session_id"] == ref_session
        assert Keyword.get(opts, :session_id) == ref_session
        {:ok, "result"}
      end)

      SnakeBridge.SessionContext.with_session([session_id: context_session], fn ->
        {:ok, _} = SnakeBridge.Runtime.call_method(ref, :method, [])
      end)
    end
  end
end
```

### Step 2: Run Tests to Verify They Fail

```bash
mix test test/snakebridge/session_consistency_test.exs
```

Expected: Tests for broken paths should fail.

### Step 3: Fix `call/4` for Atom Modules (lines 56-70)

**Current Code:**
```elixir
def call(module, function, args, opts) when is_atom(module) do
  {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
  encoded_args = encode_args(args ++ extra_args)
  encoded_kwargs = encode_kwargs(kwargs)
  payload = base_payload(module, function, encoded_args, encoded_kwargs, idempotent)
  session_id = Map.get(payload, "session_id")  # Gets from payload (wrong)
  runtime_opts = ensure_session_opt(runtime_opts, session_id)
  # ...
end
```

**Fixed Code:**
```elixir
def call(module, function, args, opts) when is_atom(module) do
  {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
  encoded_args = encode_args(args ++ extra_args)
  encoded_kwargs = encode_kwargs(kwargs)
  # Determine session_id ONCE using correct priority
  session_id = resolve_session_id(runtime_opts)
  payload =
    base_payload(module, function, encoded_args, encoded_kwargs, idempotent)
    |> Map.put("session_id", session_id)
  runtime_opts = ensure_session_opt(runtime_opts, session_id)
  # ...
end
```

### Step 4: Fix `get_module_attr/3` for String Modules (lines 440-467)

**Current Code:**
```elixir
def get_module_attr(module, attr, opts) when is_binary(module) do
  {_kwargs, _idempotent, _extra_args, runtime_opts} = split_opts(opts)
  attr_name = to_string(attr)
  session_id = current_session_id()  # Wrong - ignores runtime_opts
  # ...
end
```

**Fixed Code:**
```elixir
def get_module_attr(module, attr, opts) when is_binary(module) do
  {_kwargs, _idempotent, _extra_args, runtime_opts} = split_opts(opts)
  attr_name = to_string(attr)
  session_id = resolve_session_id(runtime_opts)  # Fixed
  # ...
end
```

### Step 5: Fix `get_module_attr/3` for Atom Modules (lines 470-489)

**Current Code:**
```elixir
def get_module_attr(module, attr, opts) when is_atom(module) do
  {kwargs, idempotent, _extra_args, runtime_opts} = split_opts(opts)
  encoded_kwargs = encode_kwargs(kwargs)

  payload =
    module
    |> base_payload(attr, [], encoded_kwargs, idempotent)
    |> Map.put("call_type", "module_attr")
    |> Map.put("attr", to_string(attr))

  session_id = Map.get(payload, "session_id")  # Wrong
  # ...
end
```

**Fixed Code:**
```elixir
def get_module_attr(module, attr, opts) when is_atom(module) do
  {kwargs, idempotent, _extra_args, runtime_opts} = split_opts(opts)
  encoded_kwargs = encode_kwargs(kwargs)
  session_id = resolve_session_id(runtime_opts)  # Fixed

  payload =
    module
    |> base_payload(attr, [], encoded_kwargs, idempotent)
    |> Map.put("call_type", "module_attr")
    |> Map.put("attr", to_string(attr))
    |> Map.put("session_id", session_id)

  runtime_opts = ensure_session_opt(runtime_opts, session_id)
  # ...
end
```

### Step 6: Fix `call_class/4` (lines 369-391)

**Current Code:**
```elixir
def call_class(module, function, args \\ [], opts \\ []) do
  {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
  # ...
  payload =
    module
    |> base_payload(function, encoded_args, encoded_kwargs, idempotent)
    |> Map.put("call_type", "class")
    |> Map.put("class", python_class_name(module))

  session_id = Map.get(payload, "session_id")  # Wrong
  # ...
end
```

**Fixed Code:**
```elixir
def call_class(module, function, args \\ [], opts \\ []) do
  {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
  encoded_args = encode_args(args ++ extra_args)
  encoded_kwargs = encode_kwargs(kwargs)
  session_id = resolve_session_id(runtime_opts)  # Fixed

  payload =
    module
    |> base_payload(function, encoded_args, encoded_kwargs, idempotent)
    |> Map.put("call_type", "class")
    |> Map.put("class", python_class_name(module))
    |> Map.put("session_id", session_id)

  runtime_opts = ensure_session_opt(runtime_opts, session_id)
  # ...
end
```

### Step 7: Fix `call_helper/3` with List Opts (lines 134-148)

**Current Code:**
```elixir
def call_helper(helper, args, opts) when is_list(opts) do
  {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
  encoded_args = encode_args(args ++ extra_args)
  encoded_kwargs = encode_kwargs(kwargs)
  payload = helper_payload(helper, encoded_args, encoded_kwargs, idempotent)
  session_id = Map.get(payload, "session_id")  # Wrong
  runtime_opts = ensure_session_opt(runtime_opts, session_id)
  # ...
end
```

**Fixed Code:**
```elixir
def call_helper(helper, args, opts) when is_list(opts) do
  {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
  encoded_args = encode_args(args ++ extra_args)
  encoded_kwargs = encode_kwargs(kwargs)
  session_id = resolve_session_id(runtime_opts)  # Fixed
  payload =
    helper_payload(helper, encoded_args, encoded_kwargs, idempotent)
    |> Map.put("session_id", session_id)
  runtime_opts = ensure_session_opt(runtime_opts, session_id)
  # ...
end
```

### Step 8: Fix `call_helper/3` with Map Opts (lines 119-132)

The map opts variant cannot have `__runtime__`, but should still use `resolve_session_id([])`
to be consistent:

**Fixed Code:**
```elixir
def call_helper(helper, args, opts) when is_map(opts) do
  encoded_args = encode_args(args)
  encoded_kwargs = encode_kwargs(stringify_keys(opts))
  session_id = resolve_session_id([])  # Uses context/auto-session
  payload =
    helper_payload(helper, encoded_args, encoded_kwargs, false)
    |> Map.put("session_id", session_id)
  runtime_opts = ensure_session_opt([], session_id)
  # ...
end
```

### Step 9: Fix `stream/5` for Atom Modules (lines 196-216)

**Current Code:**
```elixir
def stream(module, function, args, opts, callback)
    when is_atom(module) and is_function(callback, 1) do
  {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
  encoded_args = encode_args(args ++ extra_args)
  encoded_kwargs = encode_kwargs(kwargs)
  payload = base_payload(module, function, encoded_args, encoded_kwargs, idempotent)
  session_id = Map.get(payload, "session_id")  # Wrong
  # ...
end
```

**Fixed Code:**
```elixir
def stream(module, function, args, opts, callback)
    when is_atom(module) and is_function(callback, 1) do
  {kwargs, idempotent, extra_args, runtime_opts} = split_opts(opts)
  encoded_args = encode_args(args ++ extra_args)
  encoded_kwargs = encode_kwargs(kwargs)
  session_id = resolve_session_id(runtime_opts)  # Fixed
  payload =
    base_payload(module, function, encoded_args, encoded_kwargs, idempotent)
    |> Map.put("session_id", session_id)
  runtime_opts = ensure_session_opt(runtime_opts, session_id)
  # ...
end
```

### Step 10: Run Tests Again

```bash
mix test test/snakebridge/session_consistency_test.exs
```

All tests should now pass.

### Step 11: Run Full Test Suite

```bash
mix test
```

Ensure no regressions.

### Step 12: Run Quality Checks

```bash
mix dialyzer
mix credo --strict
```

---

## FILES TO MODIFY

| File | Lines | Change |
|------|-------|--------|
| `lib/snakebridge/runtime.ex` | 56-70 | Fix `call/4` atom module to use `resolve_session_id()` |
| `lib/snakebridge/runtime.ex` | 119-132 | Fix `call_helper/3` map opts to use `resolve_session_id([])` |
| `lib/snakebridge/runtime.ex` | 134-148 | Fix `call_helper/3` list opts to use `resolve_session_id()` |
| `lib/snakebridge/runtime.ex` | 196-216 | Fix `stream/5` atom module to use `resolve_session_id()` |
| `lib/snakebridge/runtime.ex` | 369-391 | Fix `call_class/4` to use `resolve_session_id()` |
| `lib/snakebridge/runtime.ex` | 440-467 | Fix `get_module_attr/3` string module to use `resolve_session_id()` |
| `lib/snakebridge/runtime.ex` | 470-489 | Fix `get_module_attr/3` atom module to use `resolve_session_id()` |
| `test/snakebridge/session_consistency_test.exs` | NEW | Comprehensive session consistency tests |
| `CHANGELOG.md` | Unreleased section | Add changelog entry |

---

## CHANGELOG UPDATE

Add the following to the `[Unreleased]` section in `CHANGELOG.md`:

```markdown
## [Unreleased]

### Fixed
- Session ID consistency across all Runtime call paths - `__runtime__: [session_id: X]` now respected by:
  - `call/4` with atom modules
  - `get_module_attr/3` with both atom and string modules
  - `call_class/4`
  - `call_helper/3` (list opts variant)
  - `stream/5` with atom modules
- All call paths now use `resolve_session_id()` for consistent priority: runtime_opts > ref > context > auto-session
```

---

## VERIFICATION

After completing the implementation, run these commands:

```bash
# Run session consistency tests
mix test test/snakebridge/session_consistency_test.exs --trace

# Run all tests to check for regressions
mix test

# Run static analysis
mix dialyzer

# Run code quality check
mix credo --strict

# Verify the changes
git diff lib/snakebridge/runtime.ex
```

### Expected Outcomes

1. All session consistency tests pass
2. No test regressions
3. Dialyzer reports no warnings
4. Credo reports no issues (or only pre-existing ones)

---

## NOTES

- The `base_payload/5` function still uses `current_session_id()` internally, but we override the session_id in the payload after it's built. This maintains backward compatibility while fixing the consistency issue.

- The `helper_payload/5` function also uses `current_session_id()` internally - we apply the same fix pattern.

- The map opts variant of `call_helper/3` cannot receive `__runtime__` options (since it takes a map, not a keyword list). We use `resolve_session_id([])` to ensure it goes through the same code path but falls back to context/auto-session.

- Do not modify `resolve_session_id/2` itself - it already implements the correct priority logic.
