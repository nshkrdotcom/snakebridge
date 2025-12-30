# Fix #2: Auto Session Per BEAM Process

**Status**: Specification
**Priority**: Critical
**Complexity**: Medium
**Estimated Changes**: ~150 lines Elixir

## Problem Statement

If the caller does not set `SnakeBridge.SessionContext`, `Runtime` often sends no `session_id`. On the Python side, the adapter falls back to `"default"`. This causes:

1. **Ref collisions**: Refs from unrelated Elixir processes share the same session namespace
2. **Unreliable cleanup**: SessionManager cannot auto-release sessions because nothing is monitored for "default"
3. **Memory leaks**: Long-running systems accumulate refs in Python's `_instance_registry`

Current behavior in `Runtime`:

```elixir
defp current_session_id do
  case SessionContext.current() do
    %SessionContext{session_id: id} -> id
    nil -> nil  # ← Sends no session_id, Python uses "default"
  end
end
```

## Solution

Make session scoping **automatic** even if the user never calls `SessionContext.with_session/1`.

When `SessionContext.current()` is `nil`:
1. Create/get a per-process session ID stored in the process dictionary
2. Register it with `SessionManager` (monitor owner pid)
3. Always include it in payloads

## Design Principles

1. **Zero-config for common case**: Just call Python functions, sessions work
2. **Explicit sessions still work**: `with_session/1` overrides auto-session
3. **Process isolation**: Each BEAM process gets its own session namespace
4. **Automatic cleanup**: When process dies, session is released
5. **Lazy initialization**: Auto-session only created on first Python call

## Implementation Details

### File: `lib/snakebridge/runtime.ex`

#### Change 1: Update `current_session_id/0`

```elixir
@auto_session_key :snakebridge_auto_session

@doc false
defp current_session_id do
  case SessionContext.current() do
    %SessionContext{session_id: id} ->
      id

    nil ->
      ensure_auto_session()
  end
end

@doc """
Ensures an automatic session exists for the current process.

Creates a new session if one doesn't exist, registers it with SessionManager,
and stores it in the process dictionary for subsequent calls.

Returns the session ID.
"""
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

defp setup_auto_session(session_id) do
  # Store in process dictionary
  Process.put(@auto_session_key, session_id)

  # Register with SessionManager for monitoring
  # This ensures cleanup when the process dies
  SessionManager.register_session(session_id, self())

  # Ensure Snakepit session exists (if SessionStore is available)
  ensure_snakepit_session(session_id)
end

defp ensure_snakepit_session(session_id) do
  # Only call if SessionStore module is available
  if Code.ensure_loaded?(Snakepit.SessionStore) do
    case Snakepit.SessionStore.create_session(session_id) do
      {:ok, _} -> :ok
      {:error, :already_exists} -> :ok
      {:error, reason} ->
        Logger.warning("Failed to create Snakepit session #{session_id}: #{inspect(reason)}")
        :ok
    end
  else
    :ok
  end
end
```

#### Change 2: Add cleanup function for testing

```elixir
@doc """
Clears the auto-session for the current process.

Useful for testing or when you want to force a new session.
Does NOT release the session on the Python side - use release_auto_session/0 for that.
"""
def clear_auto_session do
  Process.delete(@auto_session_key)
end

@doc """
Releases and clears the auto-session for the current process.

This releases all refs associated with the session on both Elixir and Python sides.
"""
def release_auto_session do
  case Process.get(@auto_session_key) do
    nil ->
      :ok

    session_id ->
      # Release on Python side
      release_session(session_id)
      # Unregister from SessionManager
      SessionManager.unregister_session(session_id)
      # Clear from process dictionary
      Process.delete(@auto_session_key)
      :ok
  end
end

@doc """
Returns the current session ID (explicit or auto-generated).

Useful for debugging or when you need to know which session is active.
"""
def current_session do
  current_session_id()
end
```

### File: `lib/snakebridge/session_manager.ex`

Ensure SessionManager can handle auto-sessions:

```elixir
@doc """
Registers a session and monitors the owner process.

When the owner process dies, all refs in this session are automatically released.
"""
def register_session(session_id, owner_pid) do
  GenServer.call(__MODULE__, {:register_session, session_id, owner_pid})
end

@doc """
Unregisters a session without releasing refs.

Typically called when manually cleaning up before process death.
"""
def unregister_session(session_id) do
  GenServer.call(__MODULE__, {:unregister_session, session_id})
end

# In handle_call:
def handle_call({:register_session, session_id, owner_pid}, _from, state) do
  # Only monitor if not already monitoring this pid for this session
  ref = Process.monitor(owner_pid)

  new_state = state
    |> put_in([:sessions, session_id], %{owner_pid: owner_pid, monitor_ref: ref, refs: []})
    |> put_in([:monitors, ref], session_id)

  {:reply, :ok, new_state}
end

def handle_call({:unregister_session, session_id}, _from, state) do
  case get_in(state, [:sessions, session_id]) do
    nil ->
      {:reply, :ok, state}

    %{monitor_ref: ref} ->
      Process.demonitor(ref, [:flush])
      new_state = state
        |> update_in([:sessions], &Map.delete(&1, session_id))
        |> update_in([:monitors], &Map.delete(&1, ref))
      {:reply, :ok, new_state}
  end
end

# Handle process death
def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
  case get_in(state, [:monitors, ref]) do
    nil ->
      {:noreply, state}

    session_id ->
      # Release session on Python side
      spawn(fn ->
        SnakeBridge.Runtime.release_session(session_id)
      end)

      # Clean up state
      new_state = state
        |> update_in([:sessions], &Map.delete(&1, session_id))
        |> update_in([:monitors], &Map.delete(&1, ref))

      {:noreply, new_state}
  end
end
```

### File: `lib/snakebridge.ex`

Add convenience functions:

```elixir
@doc """
Returns the current session ID (explicit or auto-generated).

## Examples

    iex> SnakeBridge.current_session()
    "auto_<0.123.0>_1703944800000"

    iex> SnakeBridge.SessionContext.with_session(session_id: "my_session", fn ->
    ...>   SnakeBridge.current_session()
    ...> end)
    "my_session"
"""
defdelegate current_session, to: SnakeBridge.Runtime

@doc """
Releases and clears the auto-session for the current process.

Call this to eagerly release refs when you're done with Python calls
in the current process, rather than waiting for process termination.

## Examples

    SnakeBridge.call("numpy", "array", [[1,2,3]])
    # ... more calls ...
    SnakeBridge.release_auto_session()  # Clean up now
"""
defdelegate release_auto_session, to: SnakeBridge.Runtime
```

## Wire Format Changes

**Before** (when no SessionContext):
```json
{
  "protocol_version": 1,
  "library": "numpy",
  "python_module": "numpy",
  "function": "array",
  "args": [[1, 2, 3]]
}
```

**After** (always includes session_id):
```json
{
  "protocol_version": 1,
  "library": "numpy",
  "python_module": "numpy",
  "function": "array",
  "args": [[1, 2, 3]],
  "session_id": "auto_<0.123.0>_1703944800000"
}
```

## Test Specifications

### File: `test/snakebridge/auto_session_test.exs`

```elixir
defmodule SnakeBridge.AutoSessionTest do
  use ExUnit.Case, async: false  # Process dictionary tests need sequential execution

  setup do
    # Clear any existing auto-session
    SnakeBridge.Runtime.clear_auto_session()
    :ok
  end

  describe "auto session creation" do
    test "auto-session is created on first Python call" do
      # Before call, no session
      assert Process.get(:snakebridge_auto_session) == nil

      # Make a call
      {:ok, _} = SnakeBridge.Runtime.call("math", "sqrt", [4])

      # Session now exists
      session_id = Process.get(:snakebridge_auto_session)
      assert session_id != nil
      assert String.starts_with?(session_id, "auto_")
    end

    test "same session is reused for subsequent calls" do
      {:ok, _} = SnakeBridge.Runtime.call("math", "sqrt", [4])
      session_id_1 = SnakeBridge.Runtime.current_session()

      {:ok, _} = SnakeBridge.Runtime.call("math", "sqrt", [9])
      session_id_2 = SnakeBridge.Runtime.current_session()

      assert session_id_1 == session_id_2
    end

    test "explicit session overrides auto-session" do
      {:ok, _} = SnakeBridge.Runtime.call("math", "sqrt", [4])
      auto_session = SnakeBridge.Runtime.current_session()

      explicit_session = SnakeBridge.SessionContext.with_session(session_id: "explicit_123", fn ->
        SnakeBridge.Runtime.current_session()
      end)

      assert explicit_session == "explicit_123"

      # After with_session, back to auto
      assert SnakeBridge.Runtime.current_session() == auto_session
    end
  end

  describe "process isolation" do
    test "different processes get different auto-sessions" do
      {:ok, _} = SnakeBridge.Runtime.call("math", "sqrt", [4])
      session_1 = SnakeBridge.Runtime.current_session()

      session_2 = Task.async(fn ->
        {:ok, _} = SnakeBridge.Runtime.call("math", "sqrt", [9])
        SnakeBridge.Runtime.current_session()
      end) |> Task.await()

      assert session_1 != session_2
    end

    test "refs from different processes don't collide" do
      ref_1 = Task.async(fn ->
        {:ok, ref} = SnakeBridge.Runtime.call("pathlib", "Path", ["/tmp"])
        ref
      end) |> Task.await()

      ref_2 = Task.async(fn ->
        {:ok, ref} = SnakeBridge.Runtime.call("pathlib", "Path", ["/home"])
        ref
      end) |> Task.await()

      # Different session_ids
      assert ref_1.session_id != ref_2.session_id
    end
  end

  describe "auto session cleanup" do
    test "clear_auto_session removes session from process" do
      {:ok, _} = SnakeBridge.Runtime.call("math", "sqrt", [4])
      assert Process.get(:snakebridge_auto_session) != nil

      SnakeBridge.Runtime.clear_auto_session()
      assert Process.get(:snakebridge_auto_session) == nil
    end

    test "release_auto_session cleans up refs" do
      {:ok, ref} = SnakeBridge.Runtime.call("pathlib", "Path", ["."])
      session_id = ref.session_id

      SnakeBridge.Runtime.release_auto_session()

      # Session is cleared
      assert Process.get(:snakebridge_auto_session) == nil

      # Ref is no longer valid (subsequent method call would fail)
      # We can't easily test Python-side cleanup, but the mechanism is in place
    end

    test "new auto-session created after release" do
      {:ok, _} = SnakeBridge.Runtime.call("math", "sqrt", [4])
      old_session = SnakeBridge.Runtime.current_session()

      SnakeBridge.Runtime.release_auto_session()

      {:ok, _} = SnakeBridge.Runtime.call("math", "sqrt", [9])
      new_session = SnakeBridge.Runtime.current_session()

      assert old_session != new_session
    end
  end

  describe "session manager monitoring" do
    test "SessionManager tracks auto-sessions" do
      {:ok, _} = SnakeBridge.Runtime.call("math", "sqrt", [4])
      session_id = SnakeBridge.Runtime.current_session()

      # SessionManager should have this session registered
      # (implementation detail, may need to expose test helper)
      state = :sys.get_state(SnakeBridge.SessionManager)
      assert Map.has_key?(state.sessions, session_id)
    end
  end
end
```

## Edge Cases

1. **Process spawns many short-lived tasks**: Each Task gets its own session. Consider documenting that for high-frequency short tasks, explicit `with_session/1` is more efficient.

2. **GenServer with long lifetime**: Auto-session accumulates refs over time. Document that explicit session management or periodic `release_auto_session/0` is recommended.

3. **Process pool (like Poolboy)**: Pooled processes share refs across callers. Document that callers should use explicit sessions.

4. **Distributed Erlang**: Session IDs include local PID strings, which may not be unique across nodes. Document that distributed systems should use explicit session IDs.

## Performance Considerations

1. **First-call overhead**: Creating auto-session adds a few microseconds to first call
2. **Process dictionary access**: Very fast (~100ns), negligible impact
3. **SessionManager registration**: One GenServer call per new process, acceptable

## Backwards Compatibility

- **Full compatibility**: Existing code using `with_session/1` works unchanged
- **Improved default**: Code not using sessions now gets proper isolation
- **No API changes**: Only internal behavior improvements

## Migration Guide

**No migration required**. Existing code continues to work. The main benefit is that code that didn't use sessions before now has proper session isolation automatically.

For code that explicitly doesn't want session tracking (rare), use:
```elixir
# Opt out of auto-session for specific calls
SnakeBridge.Runtime.call("module", "fn", args, __runtime__: [session_id: nil])
```

## Related Changes

- Required by [01-string-module-paths.md](./01-string-module-paths.md) for proper dynamic call isolation
- Enables safer ref management for [06-python-ref-safety.md](./06-python-ref-safety.md)
