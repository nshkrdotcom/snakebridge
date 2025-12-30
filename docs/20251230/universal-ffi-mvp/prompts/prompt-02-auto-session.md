# Prompt 02: Auto Session Per BEAM Process

**Objective**: Implement automatic session creation per BEAM process.

**Dependencies**: Prompt 01 must be completed first.

## Required Reading

Before starting, read these files completely:

### Documentation
- `docs/20251230/universal-ffi-mvp/00-overview.md` - Full context
- `docs/20251230/universal-ffi-mvp/02-auto-session.md` - Auto session spec

### Source Files
- `lib/snakebridge/runtime.ex` - Runtime module (focus on `current_session_id/0`)
- `lib/snakebridge/session_context.ex` - Session context handling
- `lib/snakebridge/session_manager.ex` - Session lifecycle management
- `test/snakebridge/session_context_test.exs` - Existing session tests

## Problem Summary

Currently, if no `SessionContext` is set, `current_session_id/0` returns `nil`, and Python falls back to `"default"`. This causes:
1. Ref collisions across unrelated processes
2. Memory leaks (refs never released)
3. Unreliable cleanup

## Implementation Tasks

### Task 1: Update Runtime for Auto-Session

Modify `lib/snakebridge/runtime.ex`:

1. Add module attribute for process dictionary key:
   ```elixir
   @auto_session_key :snakebridge_auto_session
   ```

2. Update `current_session_id/0`:
   ```elixir
   defp current_session_id do
     case SessionContext.current() do
       %SessionContext{session_id: id} -> id
       nil -> ensure_auto_session()
     end
   end
   ```

3. Add auto-session functions:
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

   defp setup_auto_session(session_id) do
     Process.put(@auto_session_key, session_id)
     SessionManager.register_session(session_id, self())
     ensure_snakepit_session(session_id)
   end

   defp ensure_snakepit_session(session_id) do
     if Code.ensure_loaded?(Snakepit.SessionStore) do
       case Snakepit.SessionStore.create_session(session_id) do
         {:ok, _} -> :ok
         {:error, :already_exists} -> :ok
         {:error, _reason} -> :ok
       end
     else
       :ok
     end
   end
   ```

4. Add public session management functions:
   ```elixir
   @doc """
   Returns the current session ID (explicit or auto-generated).
   """
   @spec current_session() :: String.t()
   def current_session, do: current_session_id()

   @doc """
   Clears the auto-session for the current process (for testing).
   """
   @spec clear_auto_session() :: :ok
   def clear_auto_session do
     Process.delete(@auto_session_key)
     :ok
   end

   @doc """
   Releases and clears the auto-session for the current process.
   """
   @spec release_auto_session() :: :ok
   def release_auto_session do
     case Process.get(@auto_session_key) do
       nil -> :ok
       session_id ->
         release_session(session_id)
         SessionManager.unregister_session(session_id)
         Process.delete(@auto_session_key)
         :ok
     end
   end
   ```

### Task 2: Update SessionManager

Modify `lib/snakebridge/session_manager.ex`:

1. Add `unregister_session/1` if not exists:
   ```elixir
   @doc """
   Unregisters a session without releasing refs.
   """
   def unregister_session(session_id) do
     GenServer.call(__MODULE__, {:unregister_session, session_id})
   end
   ```

2. Add handler:
   ```elixir
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
   ```

3. Ensure `handle_info` for `:DOWN` releases session on Python side:
   ```elixir
   def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
     case get_in(state, [:monitors, ref]) do
       nil ->
         {:noreply, state}
       session_id ->
         # Release on Python side asynchronously
         spawn(fn -> SnakeBridge.Runtime.release_session(session_id) end)
         new_state = state
           |> update_in([:sessions], &Map.delete(&1, session_id))
           |> update_in([:monitors], &Map.delete(&1, ref))
         {:noreply, new_state}
     end
   end
   ```

### Task 3: Write Tests (TDD)

Create `test/snakebridge/auto_session_test.exs`:

```elixir
defmodule SnakeBridge.AutoSessionTest do
  use ExUnit.Case, async: false

  setup do
    SnakeBridge.Runtime.clear_auto_session()
    :ok
  end

  describe "auto session creation" do
    test "creates session on first Python call" do
      assert Process.get(:snakebridge_auto_session) == nil
      {:ok, _} = SnakeBridge.Runtime.call("math", "sqrt", [4])
      session_id = Process.get(:snakebridge_auto_session)
      assert session_id != nil
      assert String.starts_with?(session_id, "auto_")
    end

    test "reuses session for subsequent calls" do
      {:ok, _} = SnakeBridge.Runtime.call("math", "sqrt", [4])
      session_1 = SnakeBridge.Runtime.current_session()
      {:ok, _} = SnakeBridge.Runtime.call("math", "sqrt", [9])
      session_2 = SnakeBridge.Runtime.current_session()
      assert session_1 == session_2
    end

    test "explicit session overrides auto-session" do
      {:ok, _} = SnakeBridge.Runtime.call("math", "sqrt", [4])
      auto_session = SnakeBridge.Runtime.current_session()

      explicit = SnakeBridge.SessionContext.with_session(session_id: "explicit", fn ->
        SnakeBridge.Runtime.current_session()
      end)

      assert explicit == "explicit"
      assert SnakeBridge.Runtime.current_session() == auto_session
    end
  end

  describe "process isolation" do
    test "different processes get different sessions" do
      {:ok, _} = SnakeBridge.Runtime.call("math", "sqrt", [4])
      session_1 = SnakeBridge.Runtime.current_session()

      session_2 = Task.async(fn ->
        {:ok, _} = SnakeBridge.Runtime.call("math", "sqrt", [9])
        SnakeBridge.Runtime.current_session()
      end) |> Task.await()

      assert session_1 != session_2
    end
  end

  describe "session cleanup" do
    test "clear_auto_session removes from process dictionary" do
      {:ok, _} = SnakeBridge.Runtime.call("math", "sqrt", [4])
      assert Process.get(:snakebridge_auto_session) != nil
      SnakeBridge.Runtime.clear_auto_session()
      assert Process.get(:snakebridge_auto_session) == nil
    end

    test "release_auto_session creates new session on next call" do
      {:ok, _} = SnakeBridge.Runtime.call("math", "sqrt", [4])
      old = SnakeBridge.Runtime.current_session()
      :ok = SnakeBridge.Runtime.release_auto_session()
      {:ok, _} = SnakeBridge.Runtime.call("math", "sqrt", [9])
      new = SnakeBridge.Runtime.current_session()
      assert old != new
    end
  end
end
```

### Task 4: Update Existing Tests

Some existing tests may assume no session_id in payloads. Update them to expect session_id always present, or use explicit session clearing in setup.

## Verification Checklist

Run after implementation:

```bash
# Run new tests
mix test test/snakebridge/auto_session_test.exs

# Run all tests
mix test

# Check types
mix dialyzer

# Check code quality
mix credo --strict

# Verify no warnings
mix compile --warnings-as-errors
```

All must pass with:
- ✅ All tests passing
- ✅ No dialyzer errors
- ✅ No credo issues
- ✅ No compilation warnings

## CHANGELOG Entry

Update `CHANGELOG.md` 0.8.4 entry:

```markdown
### Added
- Auto-session: BEAM processes automatically get session IDs without explicit `with_session/1`
- `SnakeBridge.Runtime.current_session/0` to get current session ID
- `SnakeBridge.Runtime.release_auto_session/0` for explicit session cleanup
- `SnakeBridge.Runtime.clear_auto_session/0` for testing

### Changed
- Session ID is now always included in wire payloads (auto-generated if not explicit)

### Fixed
- Memory leaks from refs in "default" session when not using explicit `SessionContext`
- Ref collisions between unrelated Elixir processes
```

## Notes

- Auto-session is created lazily on first Python call, not process start
- Process dictionary access is very fast (~100ns)
- SessionManager monitors process and releases on death
- Explicit `with_session/1` still overrides auto-session
- The session ID format includes PID and timestamp for uniqueness
