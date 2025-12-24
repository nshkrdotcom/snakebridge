defmodule XTrack.Collector do
  @moduledoc """
  Event collector that receives tracking events from worker processes.

  This is the core state machine that:
  - Receives decoded events from any transport
  - Validates and deduplicates events
  - Maintains run state
  - Persists to storage backend
  - Broadcasts to subscribers (LiveView, etc.)

  One Collector per run. Supervised by RunManager.
  """

  use GenServer
  require Logger

  alias XTrack.IR.{
    Envelope,
    EventMeta,
    RunId,
    RunStart,
    RunEnd,
    Param,
    Metric,
    MetricBatch,
    Artifact,
    Checkpoint,
    StatusUpdate,
    LogEntry
  }

  # ============================================================================
  # Types
  # ============================================================================

  @type run_state :: %{
          run_id: RunId.t(),
          name: String.t() | nil,
          status: atom(),
          started_at: DateTime.t(),
          ended_at: DateTime.t() | nil,
          params: %{String.t() => term()},
          metrics: %{String.t() => [metric_point()]},
          artifacts: [Artifact.t()],
          checkpoints: [Checkpoint.t()],
          logs: [LogEntry.t()],
          last_seq: non_neg_integer(),
          tags: %{String.t() => String.t()},
          source: map() | nil,
          environment: map() | nil
        }

  @type metric_point :: %{
          value: number(),
          step: non_neg_integer() | nil,
          epoch: non_neg_integer() | nil,
          timestamp: DateTime.t()
        }

  @type opts :: [
          storage: module(),
          pubsub: {module(), String.t()},
          max_logs: non_neg_integer()
        ]

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    GenServer.start_link(__MODULE__, opts, name: via(run_id))
  end

  @doc "Push an event to the collector"
  @spec push_event(String.t(), Envelope.t()) :: :ok | {:error, term()}
  def push_event(run_id, %Envelope{} = envelope) do
    GenServer.call(via(run_id), {:event, envelope})
  end

  @doc "Get current run state"
  @spec get_state(String.t()) :: {:ok, run_state()} | {:error, :not_found}
  def get_state(run_id) do
    GenServer.call(via(run_id), :get_state)
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  @doc "Get metrics for a specific key"
  @spec get_metrics(String.t(), String.t()) :: {:ok, [metric_point()]} | {:error, term()}
  def get_metrics(run_id, metric_key) do
    GenServer.call(via(run_id), {:get_metrics, metric_key})
  end

  @doc "Subscribe to real-time updates for this run"
  @spec subscribe(String.t()) :: :ok
  def subscribe(run_id) do
    Phoenix.PubSub.subscribe(XTrack.PubSub, "run:#{run_id}")
  end

  defp via(run_id), do: {:via, Registry, {XTrack.Registry, {:collector, run_id}}}

  # ============================================================================
  # Server Implementation
  # ============================================================================

  @impl true
  def init(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    storage = Keyword.get(opts, :storage, XTrack.Storage.ETS)
    max_logs = Keyword.get(opts, :max_logs, 1000)

    state = %{
      run_id: %RunId{id: run_id},
      name: nil,
      status: :initializing,
      started_at: DateTime.utc_now(),
      ended_at: nil,
      params: %{},
      metrics: %{},
      artifacts: [],
      checkpoints: [],
      logs: [],
      last_seq: 0,
      tags: %{},
      source: nil,
      environment: nil,
      # Internal
      storage: storage,
      max_logs: max_logs,
      subscribers: MapSet.new()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:event, envelope}, _from, state) do
    case process_event(envelope, state) do
      {:ok, new_state} ->
        broadcast(new_state, envelope)
        maybe_persist(new_state, envelope)
        {:reply, :ok, new_state}

      {:error, reason} = error ->
        Logger.warning("Event rejected: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    # Return only the public portion of state
    public_state =
      Map.take(state, [
        :run_id,
        :name,
        :status,
        :started_at,
        :ended_at,
        :params,
        :metrics,
        :artifacts,
        :checkpoints,
        :logs,
        :last_seq,
        :tags,
        :source,
        :environment
      ])

    {:reply, {:ok, public_state}, state}
  end

  def handle_call({:get_metrics, key}, _from, state) do
    {:reply, {:ok, Map.get(state.metrics, key, [])}, state}
  end

  # ============================================================================
  # Event Processing
  # ============================================================================

  defp process_event(%Envelope{meta: meta} = envelope, state) do
    # Validate sequence (allow replays but not out of order)
    cond do
      meta.seq <= state.last_seq ->
        Logger.debug("Duplicate/replay event seq=#{meta.seq}, ignoring")
        {:ok, state}

      meta.seq > state.last_seq + 1 ->
        {:error, {:gap_in_sequence, expected: state.last_seq + 1, got: meta.seq}}

      true ->
        envelope = put_in(envelope.meta.received_at, DateTime.utc_now())
        apply_event(envelope, state)
    end
  end

  defp apply_event(%Envelope{event_type: :run_start, payload: payload}, state) do
    {:ok,
     %{
       state
       | run_id: payload.run_id || state.run_id,
         name: payload.name,
         status: :running,
         tags: payload.tags,
         source: payload.source,
         environment: payload.environment,
         last_seq: 1
     }}
  end

  defp apply_event(%Envelope{event_type: :param, payload: %Param{} = p, meta: meta}, state) do
    key =
      case p.nested_key do
        nil -> p.key
        nested -> Enum.join([p.key | nested], ".")
      end

    {:ok, %{state | params: Map.put(state.params, key, p.value), last_seq: meta.seq}}
  end

  defp apply_event(%Envelope{event_type: :metric, payload: %Metric{} = m, meta: meta}, state) do
    point = %{
      value: m.value,
      step: m.step,
      epoch: m.epoch,
      timestamp: DateTime.utc_now()
    }

    metrics = Map.update(state.metrics, m.key, [point], &[point | &1])

    {:ok, %{state | metrics: metrics, last_seq: meta.seq}}
  end

  defp apply_event(
         %Envelope{event_type: :metric_batch, payload: %MetricBatch{} = mb, meta: meta},
         state
       ) do
    now = DateTime.utc_now()

    metrics =
      Enum.reduce(mb.metrics, state.metrics, fn {key, value}, acc ->
        point = %{value: value, step: mb.step, epoch: mb.epoch, timestamp: now}
        Map.update(acc, key, [point], &[point | &1])
      end)

    {:ok, %{state | metrics: metrics, last_seq: meta.seq}}
  end

  defp apply_event(%Envelope{event_type: :artifact, payload: %Artifact{} = a, meta: meta}, state) do
    {:ok, %{state | artifacts: [a | state.artifacts], last_seq: meta.seq}}
  end

  defp apply_event(
         %Envelope{event_type: :checkpoint, payload: %Checkpoint{} = c, meta: meta},
         state
       ) do
    {:ok, %{state | checkpoints: [c | state.checkpoints], last_seq: meta.seq}}
  end

  defp apply_event(
         %Envelope{event_type: :status, payload: %StatusUpdate{} = s, meta: meta},
         state
       ) do
    {:ok, %{state | status: s.status, last_seq: meta.seq}}
  end

  defp apply_event(%Envelope{event_type: :log, payload: %LogEntry{} = l, meta: meta}, state) do
    logs = [l | state.logs] |> Enum.take(state.max_logs)
    {:ok, %{state | logs: logs, last_seq: meta.seq}}
  end

  defp apply_event(%Envelope{event_type: :run_end, payload: %RunEnd{} = r, meta: meta}, state) do
    {:ok, %{state | status: r.status, ended_at: DateTime.utc_now(), last_seq: meta.seq}}
  end

  defp apply_event(%Envelope{event_type: type}, _state) do
    {:error, {:unhandled_event_type, type}}
  end

  # ============================================================================
  # Side Effects
  # ============================================================================

  defp broadcast(state, envelope) do
    Phoenix.PubSub.broadcast(
      XTrack.PubSub,
      "run:#{state.run_id.id}",
      {:xtrack_event, envelope.event_type, envelope.payload}
    )
  rescue
    # PubSub not configured
    _ -> :ok
  end

  defp maybe_persist(state, envelope) do
    # Async persist to storage backend
    Task.start(fn ->
      state.storage.persist_event(state.run_id.id, envelope)
    end)
  rescue
    _ -> :ok
  end
end
