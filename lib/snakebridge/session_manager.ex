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
  @spec register_session(session_id(), pid()) :: :ok | {:error, :already_exists}
  def register_session(session_id, owner_pid) do
    GenServer.call(__MODULE__, {:register_session, session_id, owner_pid})
  end

  @doc """
  Registers a ref with its session for tracking.
  """
  @spec register_ref(session_id(), ref()) :: :ok | {:error, :session_not_found}
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

  @doc """
  Unregisters a session without releasing refs on the Python side.

  Typically called when manually cleaning up before process death,
  or when the caller has already released the session.
  """
  @spec unregister_session(session_id()) :: :ok
  def unregister_session(session_id) do
    GenServer.call(__MODULE__, {:unregister_session, session_id})
  end

  # Server Implementation

  @impl true
  def init(_opts) do
    state = %{
      # session_id => %{owner_pid, monitor_ref, refs, created_at}
      sessions: %{},
      # monitor_ref => session_id
      monitors: %{}
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
        state
        | sessions: Map.put(state.sessions, session_id, session_data),
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
    refs =
      case Map.get(state.sessions, session_id) do
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
  def handle_call({:unregister_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, :ok, state}

      %{monitor_ref: ref} ->
        Process.demonitor(ref, [:flush])

        new_state = %{
          state
          | sessions: Map.delete(state.sessions, session_id),
            monitors: Map.delete(state.monitors, ref)
        }

        {:reply, :ok, new_state}
    end
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
        Process.demonitor(session_data.monitor_ref, [:flush])

        Task.start(fn ->
          try do
            SnakeBridge.Runtime.release_session(session_id, [])
          rescue
            _ -> :ok
          catch
            :exit, _ -> :ok
          end
        end)

        %{
          state
          | sessions: Map.delete(state.sessions, session_id),
            monitors: Map.delete(state.monitors, session_data.monitor_ref)
        }
    end
  end
end
