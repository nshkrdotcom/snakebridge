defmodule XTrack.Snakepit do
  @moduledoc """
  Integration layer between XTrack and Snakepit.

  Snakepit manages Python process pools and sessions.
  This module bridges XTrack's tracking protocol with Snakepit's
  process management.

  ## Usage

  ### With Snakepit Pool

      # Configure pool with XTrack-aware workers
      config = %Snakepit.Config{
        pool_size: 4,
        python_path: "/usr/bin/python",
        startup_script: XTrack.Snakepit.worker_script(),
        env: XTrack.Snakepit.worker_env()
      }
      
      {:ok, pool} = Snakepit.start_pool(config)
      
      # Run tracked experiment
      {:ok, run_id} = XTrack.Snakepit.run_experiment(pool, %{
        script: "train.py",
        params: %{lr: 0.001, epochs: 10},
        name: "my_experiment"
      })

  ### With Direct Session

      {:ok, session} = Snakepit.checkout(pool)
      
      {:ok, run_id} = XTrack.Snakepit.track_session(session, 
        name: "interactive_experiment"
      )
      
      # Session events automatically tracked
      Snakepit.eval(session, "model.train()")
  """

  alias XTrack.{RunManager, Collector, IR}

  # ============================================================================
  # Worker Setup
  # ============================================================================

  @doc """
  Returns the Python script that initializes XTrack in a Snakepit worker.

  This script should be run at worker startup to set up the tracking context.
  """
  def worker_script do
    """
    import sys
    import os

    # Add xtrack to path if not installed
    xtrack_path = os.environ.get('XTRACK_PYTHON_PATH')
    if xtrack_path:
        sys.path.insert(0, xtrack_path)

    from xtrack import Tracker

    # Global tracker instance for this worker
    _xtrack_run = None

    def xtrack_start_run(**kwargs):
        global _xtrack_run
        _xtrack_run = Tracker.start_run(**kwargs)
        return _xtrack_run.run_id

    def xtrack_end_run(status='completed'):
        global _xtrack_run
        if _xtrack_run:
            _xtrack_run.end(status)
            _xtrack_run = None

    def xtrack_log_params(params):
        if _xtrack_run:
            _xtrack_run.log_params(params)

    def xtrack_log_metrics(metrics, step=None, epoch=None):
        if _xtrack_run:
            _xtrack_run.log_metrics(metrics, step=step, epoch=epoch)

    def xtrack_log_metric(key, value, step=None):
        if _xtrack_run:
            _xtrack_run.log_metric(key, value, step=step)

    def xtrack_log_artifact(path, artifact_type='other'):
        if _xtrack_run:
            _xtrack_run.log_artifact(path, artifact_type)

    def xtrack_checkpoint(path, step, metrics=None, is_best=False):
        if _xtrack_run:
            _xtrack_run.log_checkpoint(path, step, metrics=metrics, is_best=is_best)

    def xtrack_status(status, message=None, progress=None):
        if _xtrack_run:
            _xtrack_run.set_status(status, message, progress)
    """
  end

  @doc "Returns environment variables for XTrack-enabled workers"
  def worker_env(opts \\ []) do
    python_path = Keyword.get(opts, :python_path, Path.join(:code.priv_dir(:xtrack), "python"))

    [
      {"XTRACK_PYTHON_PATH", python_path},
      {"XTRACK_TRANSPORT", "stdio"}
    ]
  end

  # ============================================================================
  # Experiment Execution
  # ============================================================================

  @doc """
  Run a tracked experiment on a Snakepit pool.

  ## Options

    - `:script` - Python script to run (required)
    - `:params` - Hyperparameters to pass and log
    - `:name` - Run name
    - `:experiment_id` - Parent experiment ID
    - `:tags` - Run tags
    - `:timeout` - Execution timeout in ms

  ## Returns

    `{:ok, run_id}` or `{:error, reason}`
  """
  @spec run_experiment(pid(), map()) :: {:ok, String.t()} | {:error, term()}
  def run_experiment(pool, opts) do
    script = Map.fetch!(opts, :script)
    params = Map.get(opts, :params, %{})
    name = Map.get(opts, :name)
    experiment_id = Map.get(opts, :experiment_id)
    tags = Map.get(opts, :tags, %{})
    timeout = Map.get(opts, :timeout, :infinity)

    run_id = generate_run_id()

    # Start collector
    {:ok, _} = RunManager.start_collector(run_id)

    # Checkout worker from pool
    case Snakepit.checkout(pool, timeout: 5000) do
      {:ok, session} ->
        try do
          # Initialize tracking in worker
          init_code = """
          xtrack_start_run(
              run_id=#{inspect(run_id)},
              name=#{inspect(name)},
              experiment_id=#{inspect(experiment_id)},
              tags=#{encode_python_dict(tags)}
          )
          xtrack_log_params(#{encode_python_dict(params)})
          """

          {:ok, _} = Snakepit.eval(session, init_code)

          # Run the training script
          run_code = """
          exec(open(#{inspect(script)}).read())
          """

          result = Snakepit.eval(session, run_code, timeout: timeout)

          # End tracking
          status =
            case result do
              {:ok, _} -> "completed"
              {:error, _} -> "failed"
            end

          Snakepit.eval(session, "xtrack_end_run(#{inspect(status)})")

          {:ok, run_id}
        after
          Snakepit.checkin(pool, session)
        end

      {:error, reason} ->
        RunManager.stop_run(run_id)
        {:error, {:pool_checkout_failed, reason}}
    end
  end

  @doc """
  Track an interactive Snakepit session.

  Attaches XTrack to an existing session for manual experiment tracking.
  """
  @spec track_session(pid(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def track_session(session, opts \\ []) do
    run_id = Keyword.get_lazy(opts, :run_id, &generate_run_id/0)
    name = Keyword.get(opts, :name)
    experiment_id = Keyword.get(opts, :experiment_id)
    tags = Keyword.get(opts, :tags, %{})

    # Start collector
    {:ok, _} = RunManager.start_collector(run_id)

    # Initialize in session
    init_code = """
    xtrack_start_run(
        run_id=#{inspect(run_id)},
        name=#{inspect(name)},
        experiment_id=#{inspect(experiment_id)},
        tags=#{encode_python_dict(tags)}
    )
    """

    case Snakepit.eval(session, init_code) do
      {:ok, _} -> {:ok, run_id}
      error -> error
    end
  end

  # ============================================================================
  # Batch Execution (Grid Search, etc.)
  # ============================================================================

  @doc """
  Run a grid search over hyperparameters.

  ## Options

    - `:script` - Training script
    - `:param_grid` - Map of param name to list of values
    - `:experiment_id` - ID to group all runs
    - `:max_parallel` - Maximum concurrent runs

  ## Example

      XTrack.Snakepit.grid_search(pool, %{
        script: "train.py",
        param_grid: %{
          lr: [0.001, 0.01, 0.1],
          batch_size: [16, 32, 64]
        },
        experiment_id: "lr_batch_sweep"
      })
  """
  @spec grid_search(pid(), map()) :: {:ok, [String.t()]} | {:error, term()}
  def grid_search(pool, opts) do
    script = Map.fetch!(opts, :script)
    param_grid = Map.fetch!(opts, :param_grid)
    experiment_id = Map.get(opts, :experiment_id, generate_experiment_id())
    max_parallel = Map.get(opts, :max_parallel, 4)

    # Generate all parameter combinations
    param_combos = cartesian_product(param_grid)

    # Run in parallel with bounded concurrency
    results =
      Task.async_stream(
        param_combos,
        fn params ->
          name = params_to_name(params)

          run_experiment(pool, %{
            script: script,
            params: params,
            name: name,
            experiment_id: experiment_id,
            tags: Map.new(params, fn {k, v} -> {to_string(k), to_string(v)} end)
          })
        end,
        max_concurrency: max_parallel,
        timeout: :infinity,
        ordered: false
      )
      |> Enum.map(fn
        {:ok, {:ok, run_id}} -> run_id
        {:ok, {:error, _}} -> nil
        {:exit, _} -> nil
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, results}
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp generate_run_id do
    :crypto.strong_rand_bytes(16) |> Base.hex_encode32(case: :lower, padding: false)
  end

  defp generate_experiment_id do
    "exp_" <> (:crypto.strong_rand_bytes(8) |> Base.hex_encode32(case: :lower, padding: false))
  end

  defp encode_python_dict(map) when is_map(map) do
    inner =
      map
      |> Enum.map(fn {k, v} -> "#{inspect(to_string(k))}: #{encode_python_value(v)}" end)
      |> Enum.join(", ")

    "{#{inner}}"
  end

  defp encode_python_value(v) when is_binary(v), do: inspect(v)
  defp encode_python_value(v) when is_number(v), do: to_string(v)
  defp encode_python_value(v) when is_boolean(v), do: if(v, do: "True", else: "False")

  defp encode_python_value(v) when is_list(v) do
    "[" <> Enum.map_join(v, ", ", &encode_python_value/1) <> "]"
  end

  defp encode_python_value(v) when is_map(v), do: encode_python_dict(v)
  defp encode_python_value(nil), do: "None"

  defp cartesian_product(map) when map_size(map) == 0, do: [%{}]

  defp cartesian_product(map) do
    [{key, values} | rest] = Map.to_list(map)
    rest_combos = cartesian_product(Map.new(rest))

    for value <- values, combo <- rest_combos do
      Map.put(combo, key, value)
    end
  end

  defp params_to_name(params) do
    params
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join("_")
  end
end
