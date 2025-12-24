defmodule XTrack.IR do
  @moduledoc """
  Intermediate Representation for ML experiment tracking events.
  
  These types define the contract between any compute worker (Python, Julia, Rust)
  and the Elixir control plane. Transport-agnostic - just data.
  """

  # ============================================================================
  # Core Identity Types
  # ============================================================================

  defmodule RunId do
    @moduledoc "Globally unique run identifier"
    @type t :: %__MODULE__{
      id: String.t(),
      experiment_id: String.t() | nil,
      parent_run_id: String.t() | nil
    }
    defstruct [:id, :experiment_id, :parent_run_id]
  end

  defmodule EventMeta do
    @moduledoc "Metadata attached to every event for ordering and deduplication"
    @type t :: %__MODULE__{
      seq: non_neg_integer(),           # Monotonic sequence number within run
      timestamp_us: integer(),           # Microseconds since epoch (worker clock)
      worker_id: String.t() | nil,       # For distributed training
      received_at: DateTime.t() | nil    # Set by collector on receipt
    }
    defstruct [:seq, :timestamp_us, :worker_id, :received_at]
  end

  # ============================================================================
  # Event Types (Python → Elixir)
  # ============================================================================

  defmodule RunStart do
    @moduledoc "Signals the beginning of an experiment run"
    @type t :: %__MODULE__{
      run_id: RunId.t(),
      name: String.t() | nil,
      tags: %{String.t() => String.t()},
      source: source_info() | nil,
      environment: env_info() | nil
    }

    @type source_info :: %{
      git_commit: String.t() | nil,
      git_branch: String.t() | nil,
      git_repo: String.t() | nil,
      entrypoint: String.t() | nil,
      code_hash: String.t() | nil
    }

    @type env_info :: %{
      python_version: String.t() | nil,
      platform: String.t() | nil,
      hostname: String.t() | nil,
      gpu_info: [map()] | nil,
      env_vars: %{String.t() => String.t()} | nil
    }

    defstruct [
      :run_id,
      :name,
      tags: %{},
      source: nil,
      environment: nil
    ]
  end

  defmodule Param do
    @moduledoc "A hyperparameter or configuration value"
    @type t :: %__MODULE__{
      run_id: String.t(),
      key: String.t(),
      value: param_value(),
      nested_key: [String.t()] | nil  # For hierarchical params like optimizer.lr
    }
    @type param_value :: number() | String.t() | boolean() | [param_value()] | %{String.t() => param_value()}
    
    defstruct [:run_id, :key, :value, :nested_key]
  end

  defmodule Metric do
    @moduledoc "A tracked metric value (loss, accuracy, custom metrics)"
    @type t :: %__MODULE__{
      run_id: String.t(),
      key: String.t(),
      value: number(),
      step: non_neg_integer() | nil,      # Training step/iteration
      epoch: non_neg_integer() | nil,     # Epoch number
      context: metric_context()
    }

    @type metric_context :: %{
      phase: :train | :val | :test | nil,
      batch_size: non_neg_integer() | nil,
      dataset_size: non_neg_integer() | nil,
      aggregation: :mean | :sum | :last | nil
    }

    defstruct [:run_id, :key, :value, :step, :epoch, context: %{}]
  end

  defmodule MetricBatch do
    @moduledoc "Multiple metrics logged atomically (e.g., all metrics for one step)"
    @type t :: %__MODULE__{
      run_id: String.t(),
      step: non_neg_integer() | nil,
      epoch: non_neg_integer() | nil,
      metrics: %{String.t() => number()},
      context: Metric.metric_context()
    }

    defstruct [:run_id, :step, :epoch, :metrics, context: %{}]
  end

  defmodule Artifact do
    @moduledoc "A file artifact (model weights, plots, data samples)"
    @type t :: %__MODULE__{
      run_id: String.t(),
      path: String.t(),                    # Local path on worker
      artifact_type: artifact_type(),
      name: String.t() | nil,              # Logical name
      metadata: map(),
      size_bytes: non_neg_integer() | nil,
      checksum: String.t() | nil,          # SHA256
      upload_strategy: :inline | :reference | :stream
    }

    @type artifact_type :: 
      :model | :checkpoint | :weights | :config |
      :plot | :figure | :image |
      :data | :predictions | :embeddings |
      :log | :profile | :other

    defstruct [
      :run_id,
      :path,
      :artifact_type,
      :name,
      :size_bytes,
      :checksum,
      metadata: %{},
      upload_strategy: :reference
    ]
  end

  defmodule Checkpoint do
    @moduledoc "Training checkpoint with associated state"
    @type t :: %__MODULE__{
      run_id: String.t(),
      step: non_neg_integer(),
      epoch: non_neg_integer() | nil,
      path: String.t(),
      metrics_snapshot: %{String.t() => number()},
      is_best: boolean(),
      best_metric_key: String.t() | nil,
      metadata: map()
    }

    defstruct [
      :run_id,
      :step,
      :epoch,
      :path,
      :best_metric_key,
      metrics_snapshot: %{},
      is_best: false,
      metadata: %{}
    ]
  end

  defmodule StatusUpdate do
    @moduledoc "Run status/phase transitions"
    @type t :: %__MODULE__{
      run_id: String.t(),
      status: status(),
      message: String.t() | nil,
      progress: progress() | nil
    }

    @type status :: 
      :initializing | :running | :training | :evaluating |
      :checkpointing | :paused | :resuming |
      :finishing | :completed | :failed | :killed

    @type progress :: %{
      current: non_neg_integer(),
      total: non_neg_integer(),
      unit: String.t()  # "steps", "epochs", "samples", etc.
    }

    defstruct [:run_id, :status, :message, :progress]
  end

  defmodule LogEntry do
    @moduledoc "Structured log message from the training process"
    @type t :: %__MODULE__{
      run_id: String.t(),
      level: :debug | :info | :warning | :error,
      message: String.t(),
      logger_name: String.t() | nil,
      step: non_neg_integer() | nil,
      fields: map()
    }

    defstruct [:run_id, :level, :message, :logger_name, :step, fields: %{}]
  end

  defmodule RunEnd do
    @moduledoc "Signals run completion with final status"
    @type t :: %__MODULE__{
      run_id: String.t(),
      status: :completed | :failed | :killed,
      error: error_info() | nil,
      final_metrics: %{String.t() => number()},
      duration_ms: non_neg_integer() | nil
    }

    @type error_info :: %{
      type: String.t(),
      message: String.t(),
      traceback: String.t() | nil
    }

    defstruct [:run_id, :status, :error, :duration_ms, final_metrics: %{}]
  end

  # ============================================================================
  # Command Types (Elixir → Python) - Optional bidirectional control
  # ============================================================================

  defmodule Command do
    @moduledoc "Control commands from orchestrator to worker"
    @type t :: %__MODULE__{
      command_id: String.t(),
      type: command_type(),
      payload: map()
    }

    @type command_type ::
      :pause | :resume | :stop | :checkpoint_now |
      :update_params | :adjust_lr | :custom

    defstruct [:command_id, :type, payload: %{}]
  end

  defmodule Ack do
    @moduledoc "Acknowledgment of received event (optional)"
    @type t :: %__MODULE__{
      seq: non_neg_integer(),
      status: :ok | :error,
      error_message: String.t() | nil
    }

    defstruct [:seq, :status, :error_message]
  end

  # ============================================================================
  # Envelope - The wire format wrapper
  # ============================================================================

  defmodule Envelope do
    @moduledoc """
    Wire envelope wrapping any event with metadata.
    This is what actually gets serialized/deserialized.
    """
    @type t :: %__MODULE__{
      version: pos_integer(),
      event_type: atom(),
      meta: EventMeta.t(),
      payload: event()
    }

    @type event ::
      RunStart.t() | RunEnd.t() |
      Param.t() | Metric.t() | MetricBatch.t() |
      Artifact.t() | Checkpoint.t() |
      StatusUpdate.t() | LogEntry.t() |
      Command.t() | Ack.t()

    @current_version 1

    defstruct [
      version: @current_version,
      :event_type,
      :meta,
      :payload
    ]

    def current_version, do: @current_version
  end
end
