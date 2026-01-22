defmodule SnakeBridge.CallbackRegistry do
  @moduledoc """
  Registry for Elixir callbacks passed to Python.

  Manages callback lifecycle and provides invocation support.
  """

  use GenServer
  require Logger

  alias SnakeBridge.Runtime
  alias Snakepit.Bridge.ToolRegistry

  @tool_name "snakebridge.callback"

  @tool_metadata %{
    description: "Invoke an Elixir callback from Python",
    exposed_to_python: true,
    parameters: [
      %{name: "callback_id", type: "string", required: true},
      %{name: "args", type: "list", required: false}
    ]
  }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers an Elixir function as a callback.
  """
  @spec register(function(), pid()) :: {:ok, String.t()}
  def register(fun, owner_pid \\ self()) when is_function(fun) do
    ensure_tool_registered(current_session_id())
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

  @doc """
  Ensures the callback tool is registered for the session.
  """
  @spec ensure_tool_registered(String.t() | nil) :: :ok
  def ensure_tool_registered(nil) do
    ensure_tool_registered(Runtime.current_session())
  end

  def ensure_tool_registered(session_id) do
    if Code.ensure_loaded?(ToolRegistry) and
         Process.whereis(ToolRegistry) do
      case ToolRegistry.register_elixir_tool(
             session_id,
             @tool_name,
             &__MODULE__.handle_tool/1,
             @tool_metadata
           ) do
        :ok -> :ok
        {:error, {:duplicate_tool, _name}} -> :ok
        {:error, _reason} -> :ok
      end
    end

    :ok
  end

  @doc """
  Handles callback tool invocations from Python.
  """
  @spec handle_tool(map()) :: map()
  def handle_tool(params) when is_map(params) do
    callback_id = Map.get(params, "callback_id")
    args = params |> Map.get("args", []) |> List.wrap()
    decoded_args = Enum.map(args, &SnakeBridge.Types.decode/1)

    case invoke(callback_id, decoded_args) do
      {:ok, result} ->
        SnakeBridge.Types.encode(result)

      {:error, reason} ->
        %{"__type__" => "callback_error", "reason" => inspect(reason)}
    end
  end

  # Server Implementation

  @impl true
  def init(_opts) do
    state = %{
      callbacks: %{},
      monitors: %{}
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
      state
      | callbacks: Map.put(state.callbacks, callback_id, callback_data),
        monitors: Map.put(state.monitors, monitor_ref, callback_id)
    }

    {:reply, {:ok, callback_id}, new_state}
  end

  @impl true
  def handle_call({:invoke, callback_id, args}, _from, state) do
    case Map.get(state.callbacks, callback_id) do
      nil ->
        {:reply, {:error, :callback_not_found}, state}

      %{fun: fun, arity: arity} = _data ->
        if length(args) != arity do
          {:reply, {:error, {:arity_mismatch, arity}}, state}
        else
          try do
            result = apply(fun, args)
            {:reply, {:ok, result}, state}
          rescue
            exception ->
              {:reply, {:error, {:exception, exception}}, state}
          end
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
          state
          | callbacks: Map.delete(state.callbacks, callback_id),
            monitors: Map.delete(state.monitors, monitor_ref)
        }
    end
  end

  defp generate_callback_id do
    "cb_#{:erlang.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
  end

  defp current_session_id do
    Runtime.current_session()
  end
end
