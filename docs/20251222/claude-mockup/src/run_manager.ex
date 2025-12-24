defmodule XTrack.RunManager do
  @moduledoc """
  Supervisor for experiment runs.

  Manages:
  - Collector processes (one per run)
  - Transport processes (Port/TCP connections)
  - Run lifecycle (start, stop, cleanup)

  Provides the main API for spawning training jobs and querying runs.
  """

  use DynamicSupervisor
  require Logger

  alias XTrack.{Collector, Transport}

  # ============================================================================
  # Supervisor
  # ============================================================================

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # ============================================================================
  # Run Management API
  # ============================================================================

  @doc """
  Start a new experiment run by spawning a Python training process.

  Options:
    - :command - Path to Python executable or script (required)
    - :args - Command line arguments
    - :env - Environment variables
    - :name - Human-readable run name
    - :experiment_id - Parent experiment ID
    - :tags - Key-value tags
    - :storage - Storage backend module

  Returns {:ok, run_id} or {:error, reason}
  """
  @spec start_run(keyword()) :: {:ok, String.t()} | {:error, term()}
  def start_run(opts) do
    run_id = Keyword.get_lazy(opts, :run_id, fn -> generate_run_id() end)

    # Start collector first
    collector_opts = [
      run_id: run_id,
      storage: Keyword.get(opts, :storage, XTrack.Storage.ETS)
    ]

    collector_spec = {Collector, collector_opts}

    case DynamicSupervisor.start_child(__MODULE__, collector_spec) do
      {:ok, _pid} ->
        # Start transport to spawn Python process
        transport_opts = [
          run_id: run_id,
          command: Keyword.fetch!(opts, :command),
          args: Keyword.get(opts, :args, []),
          env: build_env(run_id, opts)
        ]

        transport_spec = {Transport.Port, transport_opts}

        case DynamicSupervisor.start_child(__MODULE__, transport_spec) do
          {:ok, _pid} ->
            Logger.info("Started run #{run_id}")
            {:ok, run_id}

          {:error, reason} ->
            # Clean up collector
            stop_run(run_id)
            {:error, {:transport_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:collector_failed, reason}}
    end
  end

  @doc """
  Start a collector for receiving events from an external process.

  Use this when the Python process is managed externally (e.g., by snakepit)
  and communicates via TCP or Unix socket.
  """
  @spec start_collector(String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_collector(run_id, opts \\ []) do
    collector_opts = [
      run_id: run_id,
      storage: Keyword.get(opts, :storage, XTrack.Storage.ETS)
    ]

    DynamicSupervisor.start_child(__MODULE__, {Collector, collector_opts})
  end

  @doc "Stop a run and its associated processes"
  @spec stop_run(String.t()) :: :ok
  def stop_run(run_id) do
    # Find and stop collector
    case Registry.lookup(XTrack.Registry, {:collector, run_id}) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      [] ->
        :ok
    end

    # Find and stop transport (if managed)
    case Registry.lookup(XTrack.Registry, {:transport, run_id}) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      [] ->
        :ok
    end

    :ok
  end

  @doc "Get state for a run"
  @spec get_run(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_run(run_id) do
    Collector.get_state(run_id)
  end

  @doc "List all active runs"
  @spec list_runs() :: [String.t()]
  def list_runs do
    Registry.select(XTrack.Registry, [
      {{{:collector, :"$1"}, :_, :_}, [], [:"$1"]}
    ])
  end

  @doc "Subscribe to events for a run"
  @spec subscribe(String.t()) :: :ok
  def subscribe(run_id) do
    Collector.subscribe(run_id)
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp generate_run_id do
    # UUID v4
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)

    :io_lib.format(
      "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b",
      [a, b, (c &&& 0x0FFF) ||| 0x4000, (d &&& 0x3FFF) ||| 0x8000, e]
    )
    |> IO.iodata_to_binary()
  end

  defp build_env(run_id, opts) do
    base_env = [
      {"XTRACK_TRANSPORT", "stdio"},
      {"XTRACK_RUN_ID", run_id}
    ]

    if exp_id = Keyword.get(opts, :experiment_id) do
      [{"XTRACK_EXPERIMENT", exp_id} | base_env]
    else
      base_env
    end
    |> Enum.concat(Keyword.get(opts, :env, []))
  end
end
