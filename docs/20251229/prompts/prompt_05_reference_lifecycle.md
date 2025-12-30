# Implementation Prompt: Domain 5 - Reference Lifecycle Management

## Context

You are implementing process-monitor-based reference lifecycle management for SnakeBridge. This is a **P0 blocking** domain.

## Required Reading

Before implementing, read these files in order:

### Critique Documents
1. `docs/20251229/critique/002_g3p.md` - Section C (memory leaks, ownership tracking)
2. `docs/20251229/critique/003_g3p.md` - Section 1A (auto-ref), 2A (garbage collection)

### Implementation Plan
3. `docs/20251229/implementation/00_master_plan.md` - Domain 5 overview

### Source Files (Elixir)
4. `lib/snakebridge/ref.ex` - Reference structure
5. `lib/snakebridge/runtime.ex` - release_ref/release_session functions (lines 146-170)
6. `lib/snakebridge/types/encoder.ex` - Type encoding fallback (line 139)
7. `lib/snakebridge/types/decoder.ex` - Type decoding

### Source Files (Python)
8. `priv/python/snakebridge_adapter.py` - Instance registry (lines 47-52, 146-160, 458-517)
9. `priv/python/snakebridge_types.py` - Type encoding fallback (lines 153-157)

### Test Files
10. `test/snakebridge/runtime_contract_test.exs` - Runtime contract tests

## Issues to Fix

### Issue 5.1: Auto-Ref for Unknown Types (P0)
**Problem**: Unknown Python types fallback to `str(value)`, breaking method chaining.
**Locations**:
- `priv/python/snakebridge_types.py` lines 153-157
- `lib/snakebridge/types/encoder.ex` line 139
**Fix**: Create auto-ref for non-primitive types instead of stringifying.

### Issue 5.2: Process-Monitor-Based Cleanup (P0)
**Problem**: Time-based TTL pruning is dangerous - refs can be pruned while still held in Elixir.
**Location**: `priv/python/snakebridge_adapter.py` lines 146-159
**Fix**: Implement Elixir-side SessionManager that monitors owner processes and releases refs on death.

### Issue 5.3: Session Context Isolation (P0)
**Problem**: Multiple Elixir processes can accidentally share session_id.
**Location**: Session ID extraction in adapter (lines 729-735)
**Fix**: Create explicit session context with per-process binding.

## TDD Implementation Steps

### Step 1: Write Tests First

Create `test/snakebridge/auto_ref_test.exs`:
```elixir
defmodule SnakeBridge.AutoRefTest do
  use ExUnit.Case, async: true

  describe "auto-ref for unknown types" do
    test "decoder handles ref structure" do
      ref_data = %{
        "__type__" => "ref",
        "__schema__" => 1,
        "id" => "abc123",
        "session_id" => "default",
        "python_module" => "pandas",
        "library" => "pandas"
      }

      result = SnakeBridge.Types.decode(ref_data)
      assert result["__type__"] == "ref"
      assert result["id"] == "abc123"
    end

    test "encoder does not stringify refs" do
      ref = %{
        "__type__" => "ref",
        "id" => "test123",
        "session_id" => "default"
      }

      encoded = SnakeBridge.Types.encode(ref)
      assert encoded["__type__"] == "ref"
      refute is_binary(encoded)
    end
  end
end
```

Create `test/snakebridge/session_manager_test.exs`:
```elixir
defmodule SnakeBridge.SessionManagerTest do
  use ExUnit.Case

  describe "session lifecycle" do
    test "session registered on first call" do
      session_id = "test_session_#{System.unique_integer()}"

      # Register a session with an owner
      :ok = SnakeBridge.SessionManager.register_session(session_id, self())

      # Verify session is tracked
      assert SnakeBridge.SessionManager.session_exists?(session_id)
    end

    test "session released when owner process dies" do
      session_id = "test_session_#{System.unique_integer()}"

      # Spawn a process that registers a session
      owner = spawn(fn ->
        SnakeBridge.SessionManager.register_session(session_id, self())
        receive do
          :stop -> :ok
        end
      end)

      # Wait for registration
      Process.sleep(50)
      assert SnakeBridge.SessionManager.session_exists?(session_id)

      # Kill the owner
      Process.exit(owner, :kill)
      Process.sleep(100)

      # Session should be released
      refute SnakeBridge.SessionManager.session_exists?(session_id)
    end

    test "refs tracked per session" do
      session_id = "test_session_#{System.unique_integer()}"
      :ok = SnakeBridge.SessionManager.register_session(session_id, self())

      ref1 = %{"id" => "ref1", "session_id" => session_id}
      ref2 = %{"id" => "ref2", "session_id" => session_id}

      :ok = SnakeBridge.SessionManager.register_ref(session_id, ref1)
      :ok = SnakeBridge.SessionManager.register_ref(session_id, ref2)

      refs = SnakeBridge.SessionManager.list_refs(session_id)
      assert length(refs) == 2
    end
  end
end
```

Create `test/snakebridge/session_context_test.exs`:
```elixir
defmodule SnakeBridge.SessionContextTest do
  use ExUnit.Case

  describe "session context" do
    test "creates context with unique session_id" do
      context = SnakeBridge.SessionContext.create()
      assert is_binary(context.session_id)
      assert context.owner_pid == self()
    end

    test "with_session scopes calls to session" do
      result = SnakeBridge.SessionContext.with_session(fn ->
        context = SnakeBridge.SessionContext.current()
        assert context != nil
        assert context.owner_pid == self()
        :ok
      end)

      assert result == :ok
    end

    test "context cleaned up after block" do
      SnakeBridge.SessionContext.with_session(fn ->
        assert SnakeBridge.SessionContext.current() != nil
      end)

      # Outside block, context should be cleared
      assert SnakeBridge.SessionContext.current() == nil
    end
  end
end
```

### Step 2: Run Tests (Expect Failures)
```bash
mix test test/snakebridge/auto_ref_test.exs
mix test test/snakebridge/session_manager_test.exs
mix test test/snakebridge/session_context_test.exs
```

### Step 3: Implement Fixes

#### 3.1 Fix Python Auto-Ref Fallback
File: `priv/python/snakebridge_types.py`

Change lines 153-157 from:
```python
# For any other type, try to convert to string
try:
    return str(value)
except Exception:
    return f"<non-serializable: {type(value).__name__}>"
```

To:
```python
# For any other type, signal that it needs ref wrapping
# The adapter layer will handle actual ref creation with context
try:
    # Check if this is a complex object that should be a ref
    if hasattr(value, '__class__') and not isinstance(value, (str, bytes, int, float, bool, type(None), list, dict, tuple, set)):
        # Signal that this needs ref wrapping
        return {"__needs_ref__": True, "__type_name__": type(value).__name__, "__module__": type(value).__module__}
    return str(value)
except Exception:
    return f"<non-serializable: {type(value).__name__}>"
```

#### 3.2 Update Adapter to Handle Auto-Ref Signal
File: `priv/python/snakebridge_adapter.py`

Add/modify encode_result function:
```python
def encode_result(result, session_id, python_module, library):
    """Encode a result, creating refs for complex objects."""
    encoded = encode(result)

    # Check if encode signaled need for ref
    if isinstance(encoded, dict) and encoded.get("__needs_ref__"):
        return _make_ref(session_id, result, python_module, library)

    return encoded
```

#### 3.3 Create SessionManager
File: `lib/snakebridge/session_manager.ex` (new file)

```elixir
defmodule SnakeBridge.SessionManager do
  @moduledoc """
  Manages Python session lifecycle with process monitoring.

  Sessions are automatically released when their owner process dies,
  preventing memory leaks in long-running applications.
  """

  use GenServer
  require Logger

  @type session_id :: String.t()
  @type ref :: map()

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a new session with an owner process.
  The session will be released when the owner dies.
  """
  @spec register_session(session_id(), pid()) :: :ok
  def register_session(session_id, owner_pid) do
    GenServer.call(__MODULE__, {:register_session, session_id, owner_pid})
  end

  @doc """
  Registers a ref with its session for tracking.
  """
  @spec register_ref(session_id(), ref()) :: :ok
  def register_ref(session_id, ref) do
    GenServer.call(__MODULE__, {:register_ref, session_id, ref})
  end

  @doc """
  Checks if a session exists.
  """
  @spec session_exists?(session_id()) :: boolean()
  def session_exists?(session_id) do
    GenServer.call(__MODULE__, {:session_exists?, session_id})
  end

  @doc """
  Lists all refs in a session.
  """
  @spec list_refs(session_id()) :: [ref()]
  def list_refs(session_id) do
    GenServer.call(__MODULE__, {:list_refs, session_id})
  end

  @doc """
  Explicitly releases a session and all its refs.
  """
  @spec release_session(session_id()) :: :ok
  def release_session(session_id) do
    GenServer.call(__MODULE__, {:release_session, session_id})
  end

  # Server Implementation

  @impl true
  def init(_opts) do
    state = %{
      sessions: %{},      # session_id => %{owner_pid, monitor_ref, refs, created_at}
      monitors: %{}       # monitor_ref => session_id
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:register_session, session_id, owner_pid}, _from, state) do
    if Map.has_key?(state.sessions, session_id) do
      {:reply, {:error, :already_exists}, state}
    else
      monitor_ref = Process.monitor(owner_pid)

      session_data = %{
        owner_pid: owner_pid,
        monitor_ref: monitor_ref,
        refs: [],
        created_at: System.system_time(:second)
      }

      new_state = %{
        state |
        sessions: Map.put(state.sessions, session_id, session_data),
        monitors: Map.put(state.monitors, monitor_ref, session_id)
      }

      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:register_ref, session_id, ref}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      session_data ->
        updated = %{session_data | refs: [ref | session_data.refs]}
        new_state = put_in(state.sessions[session_id], updated)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:session_exists?, session_id}, _from, state) do
    {:reply, Map.has_key?(state.sessions, session_id), state}
  end

  @impl true
  def handle_call({:list_refs, session_id}, _from, state) do
    refs = case Map.get(state.sessions, session_id) do
      nil -> []
      session_data -> session_data.refs
    end
    {:reply, refs, state}
  end

  @impl true
  def handle_call({:release_session, session_id}, _from, state) do
    new_state = do_release_session(state, session_id)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, state) do
    case Map.get(state.monitors, monitor_ref) do
      nil ->
        {:noreply, state}

      session_id ->
        Logger.debug("Session owner died, releasing session: #{session_id}")
        new_state = do_release_session(state, session_id)
        {:noreply, new_state}
    end
  end

  defp do_release_session(state, session_id) do
    case Map.get(state.sessions, session_id) do
      nil ->
        state

      session_data ->
        # Demonitor if still alive
        Process.demonitor(session_data.monitor_ref, [:flush])

        # Call Python to release the session
        spawn(fn ->
          SnakeBridge.Runtime.release_session(session_id, [])
        end)

        %{
          state |
          sessions: Map.delete(state.sessions, session_id),
          monitors: Map.delete(state.monitors, session_data.monitor_ref)
        }
    end
  end
end
```

#### 3.4 Create SessionContext
File: `lib/snakebridge/session_context.ex` (new file)

```elixir
defmodule SnakeBridge.SessionContext do
  @moduledoc """
  Provides scoped session context for Python calls.

  ## Usage

      SnakeBridge.SessionContext.with_session(fn ->
        # All Python calls here use the same session
        Python.some_function()
        Python.another_function()
      end)
  """

  @context_key :snakebridge_session_context

  defstruct [
    :session_id,
    :owner_pid,
    :created_at,
    max_refs: 10_000,
    ttl_seconds: 3600,
    tags: %{}
  ]

  @type t :: %__MODULE__{
    session_id: String.t(),
    owner_pid: pid(),
    created_at: integer(),
    max_refs: pos_integer(),
    ttl_seconds: pos_integer(),
    tags: map()
  }

  @doc """
  Creates a new session context.
  """
  @spec create(keyword()) :: t()
  def create(opts \\ []) do
    %__MODULE__{
      session_id: Keyword.get(opts, :session_id, generate_session_id()),
      owner_pid: Keyword.get(opts, :owner_pid, self()),
      created_at: System.system_time(:second),
      max_refs: Keyword.get(opts, :max_refs, 10_000),
      ttl_seconds: Keyword.get(opts, :ttl_seconds, 3600),
      tags: Keyword.get(opts, :tags, %{})
    }
  end

  @doc """
  Gets the current session context from process dictionary.
  """
  @spec current() :: t() | nil
  def current do
    Process.get(@context_key)
  end

  @doc """
  Sets the current session context in process dictionary.
  """
  @spec put_current(t()) :: t() | nil
  def put_current(context) do
    Process.put(@context_key, context)
  end

  @doc """
  Clears the current session context.
  """
  @spec clear_current() :: t() | nil
  def clear_current do
    Process.delete(@context_key)
  end

  @doc """
  Executes a function within a session context.

  The session is automatically registered and will be released
  when the owner process dies.
  """
  @spec with_session(keyword(), (-> result)) :: result when result: term()
  def with_session(opts \\ [], fun) do
    context = create(opts)

    # Register session with manager
    :ok = SnakeBridge.SessionManager.register_session(context.session_id, context.owner_pid)

    # Store in process dictionary
    old_context = put_current(context)

    try do
      fun.()
    after
      # Restore previous context (or clear)
      if old_context do
        put_current(old_context)
      else
        clear_current()
      end
    end
  end

  defp generate_session_id do
    "session_#{:erlang.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
  end
end
```

#### 3.5 Add SessionManager to Application Supervision
File: `lib/snakebridge/application.ex`

Add to children list:
```elixir
children = [
  # ... existing children
  SnakeBridge.SessionManager
]
```

### Step 4: Run Tests (Expect Pass)
```bash
mix test test/snakebridge/auto_ref_test.exs
mix test test/snakebridge/session_manager_test.exs
mix test test/snakebridge/session_context_test.exs
mix test
```

### Step 5: Run Full Quality Checks
```bash
mix compile --warnings-as-errors
mix dialyzer
mix credo --strict
```

### Step 6: Update Examples

Create `examples/session_lifecycle_example/` to demonstrate:
- Auto-ref for complex objects
- Session-scoped operations
- Automatic cleanup on process death
- Manual session release

Update `examples/run_all.sh` with new example.

### Step 7: Update Documentation

Update `README.md`:
- Document session lifecycle management
- Document auto-ref behavior
- Document `SessionContext.with_session/2`
- Add configuration options for TTL

## Acceptance Criteria

- [ ] Unknown Python types return refs, not strings
- [ ] Sessions auto-released when owner process dies
- [ ] `with_session/2` provides scoped context
- [ ] Refs tracked per session
- [ ] Python-side release_session called on cleanup
- [ ] No memory leaks in long-running applications
- [ ] All existing tests pass
- [ ] New tests for this domain pass
- [ ] No dialyzer errors
- [ ] No credo warnings

## Dependencies

This domain depends on:
- Domain 1 (Type System) - auto-ref encoding

This domain enables:
- Domain 6 (Python Idioms) - generator refs need lifecycle
- Domain 4 (Dynamic Dispatch) - dynamic refs need cleanup
