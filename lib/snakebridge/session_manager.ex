defmodule SnakeBridge.SessionManager do
  @moduledoc """
  Manages Python session lifecycle with process monitoring.

  Sessions are automatically released when all owner processes die,
  preventing memory leaks in long-running applications.

  Cleanup logs are opt-in via config. Use
  `config :snakebridge, session_cleanup_log_level: :debug` to enable.
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
  Registers a session owner process.
  The session will be released when the last owner dies.
  """
  @spec register_session(session_id(), pid()) :: :ok
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
      # session_id => %{owners: %{pid => monitor_ref}, refs, created_at}
      sessions: %{},
      # monitor_ref => {session_id, owner_pid}
      monitors: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:register_session, session_id, owner_pid}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        monitor_ref = Process.monitor(owner_pid)

        session_data = %{
          owners: %{owner_pid => monitor_ref},
          refs: [],
          created_at: System.system_time(:second)
        }

        new_state = %{
          state
          | sessions: Map.put(state.sessions, session_id, session_data),
            monitors: Map.put(state.monitors, monitor_ref, {session_id, owner_pid})
        }

        {:reply, :ok, new_state}

      session_data ->
        if Map.has_key?(session_data.owners, owner_pid) do
          {:reply, :ok, state}
        else
          monitor_ref = Process.monitor(owner_pid)
          owners = Map.put(session_data.owners, owner_pid, monitor_ref)
          updated_session = %{session_data | owners: owners}

          new_state = %{
            state
            | sessions: Map.put(state.sessions, session_id, updated_session),
              monitors: Map.put(state.monitors, monitor_ref, {session_id, owner_pid})
          }

          {:reply, :ok, new_state}
        end
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
    new_state = do_release_session(state, session_id, :manual)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unregister_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, :ok, state}

      session_data ->
        new_state = remove_session(state, session_id, session_data)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, _pid, reason}, state) do
    case Map.get(state.monitors, monitor_ref) do
      nil ->
        {:noreply, state}

      {session_id, owner_pid} ->
        state = %{state | monitors: Map.delete(state.monitors, monitor_ref)}
        new_state = handle_owner_down(state, session_id, owner_pid, reason)
        {:noreply, new_state}
    end
  end

  defp handle_owner_down(state, session_id, owner_pid, reason) do
    case Map.get(state.sessions, session_id) do
      nil ->
        state

      session_data ->
        owners = Map.delete(session_data.owners, owner_pid)
        update_or_release_session(state, session_id, session_data, owners, reason)
    end
  end

  defp update_or_release_session(state, session_id, _session_data, owners, reason)
       when map_size(owners) == 0 do
    do_release_session(state, session_id, reason)
  end

  defp update_or_release_session(state, session_id, session_data, owners, _reason) do
    updated_session = %{session_data | owners: owners}
    put_in(state.sessions[session_id], updated_session)
  end

  defp do_release_session(state, session_id, reason) do
    case Map.get(state.sessions, session_id) do
      nil ->
        state

      session_data ->
        emit_session_cleanup(session_id, reason)
        maybe_log_session_cleanup(session_id, reason)
        new_state = remove_session(state, session_id, session_data)

        # Best-effort cleanup: errors are surfaced via telemetry but do not affect state.
        Task.start(fn -> release_session_best_effort(session_id, reason) end)

        new_state
    end
  end

  defp remove_session(state, session_id, session_data) do
    monitor_refs = Map.values(session_data.owners)
    Enum.each(monitor_refs, &Process.demonitor(&1, [:flush]))

    %{
      state
      | sessions: Map.delete(state.sessions, session_id),
        monitors: Map.drop(state.monitors, monitor_refs)
    }
  end

  defp emit_session_cleanup(session_id, reason) do
    source = cleanup_source(reason)
    SnakeBridge.Telemetry.session_cleanup(session_id, source, reason)
  end

  defp emit_session_cleanup_error(session_id, reason, error) do
    source = cleanup_source(reason)
    SnakeBridge.Telemetry.session_cleanup_error(session_id, source, error)
  end

  defp cleanup_source(:manual), do: :manual
  defp cleanup_source(_reason), do: :owner_down

  defp maybe_log_session_cleanup(session_id, reason) do
    case Application.get_env(:snakebridge, :session_cleanup_log_level) do
      level when level in [:debug, :info, :warning, :error] ->
        Logger.log(level, "Releasing session #{session_id} (reason: #{inspect(reason)})")

      true ->
        Logger.debug("Releasing session #{session_id} (reason: #{inspect(reason)})")

      _ ->
        :ok
    end
  end

  defp release_session_best_effort(session_id, reason) do
    case SnakeBridge.Runtime.release_session(session_id, []) do
      :ok ->
        :ok

      {:error, error} ->
        emit_session_cleanup_error(session_id, reason, error)
    end
  rescue
    exception ->
      emit_session_cleanup_error(session_id, reason, exception)
  catch
    :exit, exit_reason ->
      emit_session_cleanup_error(session_id, reason, exit_reason)
  end
end
