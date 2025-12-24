defmodule XTrack.Storage do
  @moduledoc """
  Storage backend behaviour for persisting experiment data.
  """

  alias XTrack.IR.Envelope

  @type run_id :: String.t()
  @type query_opts :: keyword()

  @callback persist_event(run_id(), Envelope.t()) :: :ok | {:error, term()}
  @callback persist_run(run_id(), map()) :: :ok | {:error, term()}
  @callback get_run(run_id()) :: {:ok, map()} | {:error, :not_found}
  @callback list_runs(query_opts()) :: {:ok, [map()]}
  @callback get_metrics(run_id(), String.t()) :: {:ok, [map()]}
  @callback get_params(run_id()) :: {:ok, map()}
  @callback get_artifacts(run_id()) :: {:ok, [map()]}
  @callback delete_run(run_id()) :: :ok | {:error, term()}

  # ============================================================================
  # ETS Backend (In-Memory)
  # ============================================================================

  defmodule ETS do
    @moduledoc """
    In-memory storage using ETS tables.

    Fast but non-persistent. Good for development and short-lived experiments.
    Data survives process restarts but not application restarts.
    """

    @behaviour XTrack.Storage

    @runs_table :xtrack_runs
    @events_table :xtrack_events
    @metrics_table :xtrack_metrics

    def init do
      :ets.new(@runs_table, [:named_table, :set, :public, read_concurrency: true])
      :ets.new(@events_table, [:named_table, :ordered_set, :public, write_concurrency: true])
      :ets.new(@metrics_table, [:named_table, :bag, :public, write_concurrency: true])
      :ok
    rescue
      # Tables already exist
      ArgumentError -> :ok
    end

    @impl true
    def persist_event(run_id, %Envelope{} = envelope) do
      key = {run_id, envelope.meta.seq}
      :ets.insert(@events_table, {key, envelope})

      # Index metrics separately for fast queries
      case envelope do
        %{event_type: :metric, payload: metric} ->
          metric_key = {run_id, metric.key, metric.step || 0}
          :ets.insert(@metrics_table, {metric_key, metric.value, envelope.meta.timestamp_us})

        %{event_type: :metric_batch, payload: batch} ->
          Enum.each(batch.metrics, fn {key, value} ->
            metric_key = {run_id, key, batch.step || 0}
            :ets.insert(@metrics_table, {metric_key, value, envelope.meta.timestamp_us})
          end)

        _ ->
          :ok
      end

      :ok
    end

    @impl true
    def persist_run(run_id, run_state) do
      :ets.insert(@runs_table, {run_id, run_state})
      :ok
    end

    @impl true
    def get_run(run_id) do
      case :ets.lookup(@runs_table, run_id) do
        [{^run_id, state}] -> {:ok, state}
        [] -> {:error, :not_found}
      end
    end

    @impl true
    def list_runs(opts \\ []) do
      limit = Keyword.get(opts, :limit, 100)
      status = Keyword.get(opts, :status)
      experiment_id = Keyword.get(opts, :experiment_id)

      runs =
        :ets.tab2list(@runs_table)
        |> Enum.map(fn {_id, state} -> state end)
        |> maybe_filter(:status, status)
        |> maybe_filter(:experiment_id, experiment_id)
        |> Enum.sort_by(& &1.started_at, {:desc, DateTime})
        |> Enum.take(limit)

      {:ok, runs}
    end

    @impl true
    def get_metrics(run_id, metric_key) do
      pattern = {{run_id, metric_key, :_}, :_, :_}

      metrics =
        :ets.match_object(@metrics_table, pattern)
        |> Enum.map(fn {{_, _, step}, value, ts} ->
          %{step: step, value: value, timestamp_us: ts}
        end)
        |> Enum.sort_by(& &1.step)

      {:ok, metrics}
    end

    @impl true
    def get_params(run_id) do
      case get_run(run_id) do
        {:ok, %{params: params}} -> {:ok, params}
        error -> error
      end
    end

    @impl true
    def get_artifacts(run_id) do
      case get_run(run_id) do
        {:ok, %{artifacts: artifacts}} -> {:ok, artifacts}
        error -> error
      end
    end

    @impl true
    def delete_run(run_id) do
      :ets.delete(@runs_table, run_id)

      # Delete events
      :ets.match_delete(@events_table, {{run_id, :_}, :_})

      # Delete metrics
      :ets.match_delete(@metrics_table, {{run_id, :_, :_}, :_, :_})

      :ok
    end

    defp maybe_filter(runs, _key, nil), do: runs

    defp maybe_filter(runs, key, value) do
      Enum.filter(runs, &(Map.get(&1, key) == value))
    end
  end

  # ============================================================================
  # Postgres Backend
  # ============================================================================

  defmodule Postgres do
    @moduledoc """
    Persistent storage using PostgreSQL via Ecto.

    Requires the following migrations to be run.
    """

    @behaviour XTrack.Storage

    # Note: This module assumes you have an Ecto Repo configured.
    # Replace XTrack.Repo with your actual repo module.

    import Ecto.Query

    @impl true
    def persist_event(run_id, %Envelope{} = envelope) do
      event_attrs = %{
        run_id: run_id,
        seq: envelope.meta.seq,
        event_type: Atom.to_string(envelope.event_type),
        timestamp_us: envelope.meta.timestamp_us,
        worker_id: envelope.meta.worker_id,
        payload: envelope.payload |> Map.from_struct() |> Jason.encode!(),
        inserted_at: DateTime.utc_now()
      }

      case repo().insert_all("xtrack_events", [event_attrs], on_conflict: :nothing) do
        {1, _} -> :ok
        # Duplicate
        {0, _} -> :ok
        _ -> {:error, :insert_failed}
      end
    end

    @impl true
    def persist_run(run_id, run_state) do
      attrs = %{
        id: run_id,
        name: run_state.name,
        status: Atom.to_string(run_state.status),
        experiment_id: get_in(run_state, [:run_id, :experiment_id]),
        started_at: run_state.started_at,
        ended_at: run_state.ended_at,
        params: run_state.params,
        tags: run_state.tags,
        source: run_state.source,
        environment: run_state.environment,
        updated_at: DateTime.utc_now()
      }

      repo().insert_all(
        "xtrack_runs",
        [attrs],
        on_conflict: {:replace_all_except, [:id, :started_at, :inserted_at]},
        conflict_target: :id
      )

      :ok
    end

    @impl true
    def get_run(run_id) do
      query =
        from(r in "xtrack_runs",
          where: r.id == ^run_id,
          select: %{
            run_id: r.id,
            name: r.name,
            status: r.status,
            experiment_id: r.experiment_id,
            started_at: r.started_at,
            ended_at: r.ended_at,
            params: r.params,
            tags: r.tags
          }
        )

      case repo().one(query) do
        nil -> {:error, :not_found}
        run -> {:ok, %{run | status: String.to_existing_atom(run.status)}}
      end
    end

    @impl true
    def list_runs(opts \\ []) do
      limit = Keyword.get(opts, :limit, 100)
      status = Keyword.get(opts, :status)
      experiment_id = Keyword.get(opts, :experiment_id)

      query =
        from(r in "xtrack_runs",
          order_by: [desc: r.started_at],
          limit: ^limit,
          select: %{
            run_id: r.id,
            name: r.name,
            status: r.status,
            experiment_id: r.experiment_id,
            started_at: r.started_at,
            ended_at: r.ended_at
          }
        )

      query =
        if status do
          where(query, [r], r.status == ^Atom.to_string(status))
        else
          query
        end

      query =
        if experiment_id do
          where(query, [r], r.experiment_id == ^experiment_id)
        else
          query
        end

      runs =
        repo().all(query)
        |> Enum.map(&%{&1 | status: String.to_existing_atom(&1.status)})

      {:ok, runs}
    end

    @impl true
    def get_metrics(run_id, metric_key) do
      query =
        from(e in "xtrack_events",
          where: e.run_id == ^run_id,
          where: e.event_type in ["metric", "metric_batch"],
          order_by: [asc: e.seq],
          select: %{payload: e.payload, timestamp_us: e.timestamp_us}
        )

      events = repo().all(query)

      metrics =
        events
        |> Enum.flat_map(fn %{payload: payload, timestamp_us: ts} ->
          decoded = Jason.decode!(payload)

          case decoded do
            %{"key" => ^metric_key, "value" => value, "step" => step} ->
              [%{step: step, value: value, timestamp_us: ts}]

            %{"metrics" => metrics, "step" => step} when is_map_key(metrics, metric_key) ->
              [%{step: step, value: metrics[metric_key], timestamp_us: ts}]

            _ ->
              []
          end
        end)

      {:ok, metrics}
    end

    @impl true
    def get_params(run_id) do
      case get_run(run_id) do
        {:ok, %{params: params}} -> {:ok, params || %{}}
        error -> error
      end
    end

    @impl true
    def get_artifacts(run_id) do
      query =
        from(e in "xtrack_events",
          where: e.run_id == ^run_id,
          where: e.event_type == "artifact",
          order_by: [asc: e.seq],
          select: e.payload
        )

      artifacts =
        repo().all(query)
        |> Enum.map(&Jason.decode!/1)

      {:ok, artifacts}
    end

    @impl true
    def delete_run(run_id) do
      repo().delete_all(from(e in "xtrack_events", where: e.run_id == ^run_id))
      repo().delete_all(from(r in "xtrack_runs", where: r.id == ^run_id))
      :ok
    end

    defp repo do
      Application.get_env(:xtrack, :repo) || raise "XTrack.Storage.Postgres requires :repo config"
    end
  end
end

# ============================================================================
# Ecto Migrations
# ============================================================================

defmodule XTrack.Storage.Migrations.CreateTables do
  @moduledoc """
  Migration to create XTrack tables.

  Run with: mix ecto.migrate
  """

  use Ecto.Migration

  def change do
    create table(:xtrack_runs, primary_key: false) do
      add(:id, :string, primary_key: true)
      add(:name, :string)
      add(:status, :string, null: false)
      add(:experiment_id, :string)
      add(:started_at, :utc_datetime_usec, null: false)
      add(:ended_at, :utc_datetime_usec)
      add(:params, :map, default: %{})
      add(:tags, :map, default: %{})
      add(:source, :map)
      add(:environment, :map)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:xtrack_runs, [:experiment_id]))
    create(index(:xtrack_runs, [:status]))
    create(index(:xtrack_runs, [:started_at]))

    create table(:xtrack_events, primary_key: false) do
      add(:run_id, references(:xtrack_runs, type: :string, on_delete: :delete_all), null: false)
      add(:seq, :integer, null: false)
      add(:event_type, :string, null: false)
      add(:timestamp_us, :bigint, null: false)
      add(:worker_id, :string)
      add(:payload, :text, null: false)

      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:xtrack_events, [:run_id, :seq]))
    create(index(:xtrack_events, [:run_id, :event_type]))

    # Materialized view for fast metric queries (optional)
    execute(
      """
      CREATE MATERIALIZED VIEW IF NOT EXISTS xtrack_metrics AS
      SELECT 
        run_id,
        payload->>'key' as metric_key,
        (payload->>'value')::float as value,
        (payload->>'step')::integer as step,
        (payload->>'epoch')::integer as epoch,
        timestamp_us
      FROM xtrack_events
      WHERE event_type = 'metric'
      UNION ALL
      SELECT
        run_id,
        key as metric_key,
        value::float as value,
        (payload->>'step')::integer as step,
        (payload->>'epoch')::integer as epoch,
        timestamp_us
      FROM xtrack_events,
        jsonb_each_text(payload->'metrics') as kv(key, value)
      WHERE event_type = 'metric_batch'
      """,
      "DROP MATERIALIZED VIEW IF EXISTS xtrack_metrics"
    )

    execute(
      """
      CREATE INDEX IF NOT EXISTS xtrack_metrics_run_key_idx 
      ON xtrack_metrics (run_id, metric_key, step)
      """,
      "DROP INDEX IF EXISTS xtrack_metrics_run_key_idx"
    )
  end
end
