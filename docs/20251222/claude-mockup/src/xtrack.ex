defmodule XTrack do
  @moduledoc """
  XTrack - Cross-Language ML Experiment Tracking

  A transport-agnostic protocol and runtime for tracking ML experiments
  across language boundaries (Python ↔ Elixir).

  ## Architecture

  XTrack separates concerns:

  - **IR (Intermediate Representation)**: Typed event structures that define
    the contract between workers and the control plane.

  - **Wire Protocol**: Length-prefixed JSON serialization for events.

  - **Transport**: Pluggable communication (stdio, TCP, Unix socket, file).

  - **Collector**: GenServer that receives events and maintains run state.

  - **Storage**: Pluggable persistence (ETS, Postgres).

  ## Quick Start

  ### Starting a Python training job

      # Start XTrack application (usually in your supervision tree)
      XTrack.start()
      
      # Spawn a training job
      {:ok, run_id} = XTrack.start_run(
        command: "/usr/bin/python",
        args: ["train.py", "--epochs", "10"],
        name: "my_experiment",
        tags: %{"model" => "resnet50"}
      )
      
      # Subscribe to real-time updates
      XTrack.subscribe(run_id)
      
      # Receive events in your process
      receive do
        {:xtrack_event, :metric, %{key: "loss", value: value}} ->
          IO.puts("Loss: \#{value}")
      end

  ### Receiving from external process (TCP)

      # Start TCP server
      XTrack.start_tcp_server(port: 9999)
      
      # Start collector for expected run
      {:ok, _} = XTrack.start_collector("my-run-id")
      
      # Python worker connects and sends events

  ### Querying runs

      # Get run state
      {:ok, run} = XTrack.get_run(run_id)
      
      # List all runs
      {:ok, runs} = XTrack.list_runs(status: :running)
      
      # Get metrics history
      {:ok, metrics} = XTrack.get_metrics(run_id, "loss")

  ## Python Integration

  On the Python side, use the xtrack module:

      from xtrack import Tracker
      
      with Tracker.start_run(name="my_experiment") as run:
          run.log_params({"lr": 0.001})
          
          for epoch in range(10):
              loss = train_epoch()
              run.log_metrics({"loss": loss}, step=epoch)

  Environment variables control the transport:

  - `XTRACK_TRANSPORT`: stdio|tcp|unix|file|null
  - `XTRACK_HOST`: TCP host (default: localhost)
  - `XTRACK_PORT`: TCP port (default: 9999)
  - `XTRACK_SOCKET`: Unix socket path
  - `XTRACK_FILE`: File path for offline logging
  """

  alias XTrack.{RunManager, Transport, Storage}

  # ============================================================================
  # Application Start
  # ============================================================================

  @doc """
  Start the XTrack application.

  Options:
    - :storage - Storage backend (:ets or :postgres, default: :ets)
    - :repo - Ecto repo module (required for :postgres storage)
    - :pubsub - Phoenix.PubSub config
  """
  def start(opts \\ []) do
    children = [
      {Registry, keys: :unique, name: XTrack.Registry},
      {Phoenix.PubSub, name: XTrack.PubSub},
      RunManager
    ]

    # Initialize ETS storage
    if Keyword.get(opts, :storage, :ets) == :ets do
      Storage.ETS.init()
    end

    Supervisor.start_link(children, strategy: :one_for_one, name: XTrack.Supervisor)
  end

  @doc "Start TCP server for receiving events from remote workers"
  def start_tcp_server(opts \\ []) do
    DynamicSupervisor.start_child(RunManager, {Transport.TCP, opts})
  end

  # ============================================================================
  # Run Management
  # ============================================================================

  @doc """
  Start a new experiment run by spawning a Python process.

  ## Options

    - `:command` - Path to Python executable or script (required)
    - `:args` - Command line arguments (list of strings)
    - `:env` - Environment variables (keyword list or map)
    - `:name` - Human-readable run name
    - `:run_id` - Explicit run ID (auto-generated if not provided)
    - `:experiment_id` - Parent experiment ID for grouping
    - `:tags` - Key-value tags for filtering
    - `:storage` - Storage backend module

  ## Examples

      {:ok, run_id} = XTrack.start_run(
        command: "python",
        args: ["train.py", "--lr", "0.001"],
        name: "lr_sweep_001",
        experiment_id: "lr_sweep",
        tags: %{"learning_rate" => "0.001"}
      )
  """
  defdelegate start_run(opts), to: RunManager

  @doc """
  Start a collector for receiving events from an externally managed process.

  Use this when the Python process is spawned by another system (e.g., snakepit,
  Kubernetes, SLURM) and communicates via TCP or Unix socket.
  """
  defdelegate start_collector(run_id, opts \\ []), to: RunManager

  @doc "Stop a run and clean up resources"
  defdelegate stop_run(run_id), to: RunManager

  @doc "Get current state of a run"
  defdelegate get_run(run_id), to: RunManager

  @doc "List active runs"
  defdelegate list_runs(), to: RunManager

  @doc "Subscribe to real-time events for a run"
  defdelegate subscribe(run_id), to: RunManager

  # ============================================================================
  # Storage Queries
  # ============================================================================

  @doc """
  Get metrics history for a run.

  Returns list of `%{step: integer, value: float, timestamp_us: integer}`.
  """
  def get_metrics(run_id, metric_key, opts \\ []) do
    storage = Keyword.get(opts, :storage, Storage.ETS)
    storage.get_metrics(run_id, metric_key)
  end

  @doc "Get all parameters for a run"
  def get_params(run_id, opts \\ []) do
    storage = Keyword.get(opts, :storage, Storage.ETS)
    storage.get_params(run_id)
  end

  @doc "Get all artifacts for a run"
  def get_artifacts(run_id, opts \\ []) do
    storage = Keyword.get(opts, :storage, Storage.ETS)
    storage.get_artifacts(run_id)
  end

  @doc "List runs with filtering"
  def search_runs(opts \\ []) do
    storage = Keyword.get(opts, :storage, Storage.ETS)
    storage.list_runs(opts)
  end

  @doc "Delete a run and all associated data"
  def delete_run(run_id, opts \\ []) do
    storage = Keyword.get(opts, :storage, Storage.ETS)
    storage.delete_run(run_id)
  end

  # ============================================================================
  # File Replay
  # ============================================================================

  @doc """
  Replay events from a file.

  Useful for processing experiments that were run with file transport,
  or for migrating data between systems.

  ## Options

    - `:run_id` - Override run ID for all events
    - `:speed` - Replay speed (:instant, :realtime, or {:multiplier, float})
  """
  defdelegate replay_file(path, opts \\ []), to: Transport.FileReplay, as: :replay

  @doc "Stream events from a file"
  defdelegate stream_file(path), to: Transport.FileReplay, as: :stream
end

# ============================================================================
# Application
# ============================================================================

defmodule XTrack.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    XTrack.start(Application.get_all_env(:xtrack))
  end
end
