# Implementation Prompt: Domain 6 - Python Idioms Bridge

## Context

You are implementing Python idiom support (generators, context managers, callbacks) for SnakeBridge. This is a **P0 blocking** domain.

## Required Reading

Before implementing, read these files in order:

### Critique Documents
1. `docs/20251229/critique/003_g3p.md` - Sections 1B (generators), 2B (context managers), 2C (callbacks)

### Implementation Plan
2. `docs/20251229/implementation/00_master_plan.md` - Domain 6 overview

### Source Files (Elixir)
3. `lib/snakebridge/runtime.ex` - Existing stream function
4. `lib/snakebridge/types/encoder.ex` - Type encoding
5. `lib/snakebridge/types/decoder.ex` - Type decoding

### Source Files (Python)
6. `priv/python/snakebridge_adapter.py` - execute_tool handlers
7. `priv/python/snakebridge_types.py` - Type encoding (lines 153-157 fallback)

### Test Files
8. `test/snakebridge/runtime_contract_test.exs` - Runtime tests

## Issues to Fix

### Issue 6.1: Iterator/Generator Support (P0)
**Problem**: Python generators become strings instead of lazy-streamable refs.
**Location**: `priv/python/snakebridge_types.py` lines 153-157
**Fix**: Detect generators/iterators and wrap as special `stream_ref` type with Enumerable protocol.

### Issue 6.2: Context Manager Support (P0)
**Problem**: Cannot use Python `with` statement patterns; no guaranteed `__exit__` call.
**Location**: No context manager support exists
**Fix**: Create `with_python/2` macro that calls `__enter__` and guarantees `__exit__`.

### Issue 6.3: Elixir Callback Support (P1)
**Problem**: Cannot pass Elixir functions to Python as callbacks.
**Location**: No callback mechanism exists
**Fix**: Create callback registry and Python-side proxy that invokes Elixir functions.

## TDD Implementation Steps

### Step 1: Write Tests First

Create `test/snakebridge/stream_ref_test.exs`:
```elixir
defmodule SnakeBridge.StreamRefTest do
  use ExUnit.Case, async: true

  describe "generator detection" do
    test "decoder handles stream_ref type" do
      stream_data = %{
        "__type__" => "stream_ref",
        "id" => "gen123",
        "session_id" => "default",
        "stream_type" => "generator",
        "python_module" => "test",
        "library" => "test"
      }

      result = SnakeBridge.Types.decode(stream_data)
      assert %SnakeBridge.StreamRef{} = result
      assert result.stream_type == "generator"
    end
  end

  describe "Enumerable protocol" do
    test "Enum.take works on stream ref" do
      # This would require integration test with real Python
      # For unit test, verify protocol implementation exists
      assert Enumerable.impl_for(%SnakeBridge.StreamRef{})
    end
  end
end
```

Create `test/snakebridge/context_manager_test.exs`:
```elixir
defmodule SnakeBridge.ContextManagerTest do
  use ExUnit.Case

  describe "with_python macro" do
    test "calls __enter__ and __exit__" do
      # Mock ref that tracks calls
      ref = %{
        "__type__" => "ref",
        "id" => "ctx123",
        "session_id" => "default",
        "enter_called" => false,
        "exit_called" => false
      }

      # Verify payload structure for context calls
      enter_payload = SnakeBridge.WithContext.build_enter_payload(ref)
      assert enter_payload["method"] == "__enter__"

      exit_payload = SnakeBridge.WithContext.build_exit_payload(ref, nil)
      assert exit_payload["method"] == "__exit__"
      assert exit_payload["args"] == [nil, nil, nil]
    end

    test "__exit__ called even on exception" do
      # Verify try/after structure in generated code
    end
  end
end
```

Create `test/snakebridge/callback_test.exs`:
```elixir
defmodule SnakeBridge.CallbackTest do
  use ExUnit.Case

  describe "callback encoding" do
    test "function encoded as callback ref" do
      fun = fn x -> x * 2 end
      encoded = SnakeBridge.Types.encode(fun)

      assert encoded["__type__"] == "callback"
      assert is_binary(encoded["ref_id"])
      assert encoded["arity"] == 1
    end
  end

  describe "callback registry" do
    test "registers and invokes callback" do
      fun = fn x -> x + 10 end

      {:ok, callback_id} = SnakeBridge.CallbackRegistry.register(fun, self())

      result = SnakeBridge.CallbackRegistry.invoke(callback_id, [5])
      assert result == {:ok, 15}
    end

    test "cleanup on owner process death" do
      fun = fn x -> x end

      owner = spawn(fn ->
        SnakeBridge.CallbackRegistry.register(fun, self())
        receive do
          :stop -> :ok
        end
      end)

      Process.sleep(50)
      Process.exit(owner, :kill)
      Process.sleep(100)

      # Callback should be cleaned up
      # (Implementation detail: verify internal state)
    end
  end
end
```

### Step 2: Run Tests (Expect Failures)
```bash
mix test test/snakebridge/stream_ref_test.exs
mix test test/snakebridge/context_manager_test.exs
mix test test/snakebridge/callback_test.exs
```

### Step 3: Implement Fixes

#### 3.1 Create StreamRef Module with Enumerable
File: `lib/snakebridge/stream_ref.ex` (new file)

```elixir
defmodule SnakeBridge.StreamRef do
  @moduledoc """
  Represents a Python iterator or generator as an Elixir stream.

  Implements the `Enumerable` protocol for lazy iteration.
  """

  defstruct [
    :ref_id,
    :session_id,
    :stream_type,
    :python_module,
    :library,
    exhausted: false
  ]

  @type t :: %__MODULE__{
    ref_id: String.t(),
    session_id: String.t(),
    stream_type: String.t(),
    python_module: String.t(),
    library: String.t(),
    exhausted: boolean()
  }

  @doc """
  Creates a StreamRef from a decoded wire format.
  """
  def from_wire_format(map) when is_map(map) do
    %__MODULE__{
      ref_id: map["id"],
      session_id: map["session_id"],
      stream_type: map["stream_type"] || "iterator",
      python_module: map["python_module"],
      library: map["library"],
      exhausted: false
    }
  end

  @doc """
  Converts back to wire format for Python calls.
  """
  def to_wire_format(%__MODULE__{} = ref) do
    %{
      "__type__" => "ref",
      "id" => ref.ref_id,
      "session_id" => ref.session_id,
      "python_module" => ref.python_module,
      "library" => ref.library
    }
  end
end

defimpl Enumerable, for: SnakeBridge.StreamRef do
  alias SnakeBridge.{StreamRef, Runtime}

  def count(%StreamRef{stream_type: "generator"}), do: {:error, __MODULE__}
  def count(%StreamRef{} = ref) do
    case Runtime.stream_len(ref) do
      {:ok, len} when is_integer(len) -> {:ok, len}
      _ -> {:error, __MODULE__}
    end
  end

  def member?(%StreamRef{}, _value), do: {:error, __MODULE__}

  def slice(%StreamRef{}), do: {:error, __MODULE__}

  def reduce(%StreamRef{exhausted: true}, {:cont, acc}, _fun) do
    {:done, acc}
  end

  def reduce(%StreamRef{} = ref, {:cont, acc}, fun) do
    case Runtime.stream_next(ref) do
      {:ok, value} ->
        reduce(ref, fun.(value, acc), fun)

      {:error, :stop_iteration} ->
        {:done, acc}

      {:error, reason} ->
        {:halted, {:error, reason}}
    end
  end

  def reduce(_ref, {:halt, acc}, _fun), do: {:halted, acc}
  def reduce(ref, {:suspend, acc}, fun), do: {:suspended, acc, &reduce(ref, &1, fun)}
end
```

#### 3.2 Add Stream Runtime Functions
File: `lib/snakebridge/runtime.ex`

Add new functions:
```elixir
@doc """
Gets the next item from a Python iterator/generator.
"""
@spec stream_next(SnakeBridge.StreamRef.t(), opts()) ::
  {:ok, term()} | {:error, :stop_iteration} | {:error, Snakepit.Error.t()}
def stream_next(stream_ref, opts \\ []) do
  {runtime_opts, _} = normalize_args_opts([], opts)

  wire_ref = SnakeBridge.StreamRef.to_wire_format(stream_ref)

  payload = protocol_payload()
    |> Map.put("call_type", "stream_next")
    |> Map.put("stream_ref", wire_ref)

  result = runtime_client().execute("snakebridge.call", payload, runtime_opts)

  case result do
    {:ok, %{"__type__" => "stop_iteration"}} ->
      {:error, :stop_iteration}

    {:ok, value} ->
      {:ok, SnakeBridge.Types.decode(value)}

    error ->
      error
  end
end

@doc """
Gets the length of a Python iterable (if supported).
"""
@spec stream_len(SnakeBridge.StreamRef.t(), opts()) ::
  {:ok, non_neg_integer()} | {:error, term()}
def stream_len(stream_ref, opts \\ []) do
  wire_ref = SnakeBridge.StreamRef.to_wire_format(stream_ref)
  call_method(wire_ref, :__len__, [], opts)
end
```

#### 3.3 Update Decoder for StreamRef
File: `lib/snakebridge/types/decoder.ex`

Add clause:
```elixir
def decode(%{"__type__" => "stream_ref"} = map) do
  SnakeBridge.StreamRef.from_wire_format(map)
end
```

#### 3.4 Update Python Adapter for Generators
File: `priv/python/snakebridge_adapter.py`

Add stream_next handler:
```python
if call_type == "stream_next":
    stream_ref = arguments.get("stream_ref")
    iterator = _resolve_ref(stream_ref, session_id)

    try:
        item = next(iterator)
        return encode_result(item, session_id, stream_ref.get("python_module", ""), stream_ref.get("library", ""))
    except StopIteration:
        return {"__type__": "stop_iteration"}
```

Update encode to detect generators:
```python
import inspect

def encode(value, context=None):
    # ... existing cases ...

    # Detect generators and iterators
    if inspect.isgenerator(value) or inspect.isgeneratorfunction(value):
        if context:
            return _make_stream_ref(context["session_id"], value, context.get("python_module", ""), context.get("library", ""), "generator")
        return {"__needs_stream_ref__": True, "__stream_type__": "generator"}

    if hasattr(value, '__iter__') and hasattr(value, '__next__') and not isinstance(value, (str, bytes, list, tuple, dict, set)):
        if context:
            return _make_stream_ref(context["session_id"], value, context.get("python_module", ""), context.get("library", ""), "iterator")
        return {"__needs_stream_ref__": True, "__stream_type__": "iterator"}

    # ... rest of function
```

Add stream ref creation:
```python
def _make_stream_ref(session_id: str, obj: Any, python_module: str, library: str, stream_type: str) -> dict:
    ref_id = uuid.uuid4().hex
    key = f"{session_id}:{ref_id}"
    _store_ref(key, obj)
    return {
        "__type__": "stream_ref",
        "id": ref_id,
        "session_id": session_id,
        "python_module": python_module,
        "library": library,
        "stream_type": stream_type
    }
```

#### 3.5 Create WithContext Module
File: `lib/snakebridge/with_context.ex` (new file)

```elixir
defmodule SnakeBridge.WithContext do
  @moduledoc """
  Provides Python context manager support via `with_python/2` macro.

  Ensures `__exit__` is always called, even on exception.

  ## Example

      SnakeBridge.with_python(file_ref) do
        # Use the file
        SnakeBridge.Dynamic.call(file_ref, :read, [])
      end
      # File is automatically closed
  """

  alias SnakeBridge.Runtime

  @doc """
  Executes a block with a Python context manager.

  Calls `__enter__` before the block and guarantees `__exit__` after,
  even if an exception occurs.
  """
  defmacro with_python(ref, do: block) do
    quote do
      ref = unquote(ref)

      case SnakeBridge.WithContext.call_enter(ref) do
        {:ok, context_value} ->
          try do
            var!(context) = context_value
            unquote(block)
          rescue
            e ->
              SnakeBridge.WithContext.call_exit(ref, e)
              reraise e, __STACKTRACE__
          else
            result ->
              SnakeBridge.WithContext.call_exit(ref, nil)
              result
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Calls __enter__ on a Python context manager.
  """
  @spec call_enter(map(), keyword()) :: {:ok, term()} | {:error, term()}
  def call_enter(ref, opts \\ []) do
    Runtime.call_method(ref, :__enter__, [], opts)
  end

  @doc """
  Calls __exit__ on a Python context manager.
  """
  @spec call_exit(map(), Exception.t() | nil, keyword()) :: {:ok, term()} | {:error, term()}
  def call_exit(ref, exception, opts \\ []) do
    {exc_type, exc_value, exc_tb} = if exception do
      {
        to_string(exception.__struct__),
        Exception.message(exception),
        nil  # Elixir stacktrace not directly usable
      }
    else
      {nil, nil, nil}
    end

    Runtime.call_method(ref, :__exit__, [exc_type, exc_value, exc_tb], opts)
  end

  @doc false
  def build_enter_payload(ref) do
    %{
      "call_type" => "method",
      "instance" => ref,
      "method" => "__enter__",
      "args" => []
    }
  end

  @doc false
  def build_exit_payload(ref, exception) do
    {exc_type, exc_value, exc_tb} = if exception do
      {to_string(exception.__struct__), Exception.message(exception), nil}
    else
      {nil, nil, nil}
    end

    %{
      "call_type" => "method",
      "instance" => ref,
      "method" => "__exit__",
      "args" => [exc_type, exc_value, exc_tb]
    }
  end
end
```

#### 3.6 Create Callback Registry
File: `lib/snakebridge/callback_registry.ex` (new file)

```elixir
defmodule SnakeBridge.CallbackRegistry do
  @moduledoc """
  Registry for Elixir callbacks passed to Python.

  Manages callback lifecycle and provides invocation support.
  """

  use GenServer
  require Logger

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers an Elixir function as a callback.
  """
  @spec register(function(), pid()) :: {:ok, String.t()}
  def register(fun, owner_pid \\ self()) when is_function(fun) do
    GenServer.call(__MODULE__, {:register, fun, owner_pid})
  end

  @doc """
  Invokes a registered callback with arguments.
  """
  @spec invoke(String.t(), list()) :: {:ok, term()} | {:error, term()}
  def invoke(callback_id, args) do
    GenServer.call(__MODULE__, {:invoke, callback_id, args}, :infinity)
  end

  @doc """
  Unregisters a callback.
  """
  @spec unregister(String.t()) :: :ok
  def unregister(callback_id) do
    GenServer.cast(__MODULE__, {:unregister, callback_id})
  end

  # Server Implementation

  @impl true
  def init(_opts) do
    state = %{
      callbacks: %{},    # callback_id => %{fun, owner_pid, monitor_ref, arity}
      monitors: %{}      # monitor_ref => callback_id
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:register, fun, owner_pid}, _from, state) do
    callback_id = generate_callback_id()
    monitor_ref = Process.monitor(owner_pid)
    arity = Function.info(fun)[:arity]

    callback_data = %{
      fun: fun,
      owner_pid: owner_pid,
      monitor_ref: monitor_ref,
      arity: arity
    }

    new_state = %{
      state |
      callbacks: Map.put(state.callbacks, callback_id, callback_data),
      monitors: Map.put(state.monitors, monitor_ref, callback_id)
    }

    {:reply, {:ok, callback_id}, new_state}
  end

  @impl true
  def handle_call({:invoke, callback_id, args}, _from, state) do
    case Map.get(state.callbacks, callback_id) do
      nil ->
        {:reply, {:error, :callback_not_found}, state}

      %{fun: fun} ->
        try do
          result = apply(fun, args)
          {:reply, {:ok, result}, state}
        rescue
          e ->
            {:reply, {:error, {:exception, e}}, state}
        end
    end
  end

  @impl true
  def handle_cast({:unregister, callback_id}, state) do
    new_state = do_unregister(state, callback_id)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, state) do
    case Map.get(state.monitors, monitor_ref) do
      nil ->
        {:noreply, state}

      callback_id ->
        Logger.debug("Callback owner died, unregistering: #{callback_id}")
        new_state = do_unregister(state, callback_id)
        {:noreply, new_state}
    end
  end

  defp do_unregister(state, callback_id) do
    case Map.get(state.callbacks, callback_id) do
      nil ->
        state

      %{monitor_ref: monitor_ref} ->
        Process.demonitor(monitor_ref, [:flush])

        %{
          state |
          callbacks: Map.delete(state.callbacks, callback_id),
          monitors: Map.delete(state.monitors, monitor_ref)
        }
    end
  end

  defp generate_callback_id do
    "cb_#{:erlang.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
  end
end
```

#### 3.7 Update Encoder for Functions
File: `lib/snakebridge/types/encoder.ex`

Add clause for functions:
```elixir
def encode(fun) when is_function(fun) do
  case SnakeBridge.CallbackRegistry.register(fun) do
    {:ok, callback_id} ->
      arity = Function.info(fun)[:arity]

      tagged("callback", %{
        "ref_id" => callback_id,
        "pid" => :erlang.pid_to_list(self()) |> IO.iodata_to_binary(),
        "arity" => arity
      })

    {:error, reason} ->
      raise "Failed to register callback: #{inspect(reason)}"
  end
end
```

### Step 4: Run Tests (Expect Pass)
```bash
mix test test/snakebridge/stream_ref_test.exs
mix test test/snakebridge/context_manager_test.exs
mix test test/snakebridge/callback_test.exs
mix test
```

### Step 5: Run Full Quality Checks
```bash
mix compile --warnings-as-errors
mix dialyzer
mix credo --strict
```

### Step 6: Update Examples

Create `examples/python_idioms_example/` to demonstrate:
- Iterating over Python generators lazily
- Using context managers for files/connections
- Passing callbacks to Python functions

Update `examples/run_all.sh` with new example.

### Step 7: Update Documentation

Update `README.md`:
- Document generator/iterator support
- Document `with_python` macro
- Document callback passing
- Add performance considerations

## Acceptance Criteria

- [ ] Python generators wrapped as StreamRef with Enumerable
- [ ] `Enum.map/take/reduce` work on generators lazily
- [ ] `with_python` guarantees `__exit__` on error
- [ ] Elixir functions passable to Python as callbacks
- [ ] Callbacks cleaned up when owner dies
- [ ] All existing tests pass
- [ ] New tests for this domain pass
- [ ] No dialyzer errors
- [ ] No credo warnings

## Dependencies

This domain depends on:
- Domain 1 (Type System) - encoding/decoding
- Domain 4 (Dynamic Dispatch) - method calls on refs
- Domain 5 (Reference Lifecycle) - ref cleanup

This domain enables:
- Full Python library compatibility
- Data science workflows with large datasets
