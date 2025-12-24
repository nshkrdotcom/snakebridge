# XTrack Workflows and Patterns

This document describes common workflows and implementation patterns for XTrack.

---

## Workflow 1: Single Training Run

The most basic workflow: train a model, track metrics, save checkpoints.

### Python Side

```python
from xtrack import Tracker

def train():
    with Tracker.start_run(name="resnet50_imagenet") as run:
        # 1. Log hyperparameters
        run.log_params({
            "model": "resnet50",
            "optimizer": "sgd",
            "lr": 0.1,
            "momentum": 0.9,
            "batch_size": 256,
            "epochs": 90
        })
        
        # 2. Training loop
        best_acc = 0
        for epoch in range(90):
            run.set_status("training", progress=(epoch+1, 90, "epochs"))
            
            # Train
            train_loss = train_epoch(model, train_loader, optimizer)
            run.log_metric("train_loss", train_loss, epoch=epoch)
            
            # Validate
            val_loss, val_acc = validate(model, val_loader)
            run.log_metrics({
                "val_loss": val_loss,
                "val_acc": val_acc
            }, epoch=epoch)
            
            # Checkpoint
            is_best = val_acc > best_acc
            if is_best:
                best_acc = val_acc
            
            save_checkpoint(model, optimizer, epoch, f"ckpt_{epoch}.pt")
            run.log_checkpoint(
                f"ckpt_{epoch}.pt",
                step=epoch,
                metrics={"val_acc": val_acc},
                is_best=is_best,
                best_metric_key="val_acc"
            )
        
        # 3. Save final model
        torch.save(model.state_dict(), "model_final.pt")
        run.log_artifact("model_final.pt", artifact_type="model")
```

### Elixir Side

```elixir
# Start the run
{:ok, run_id} = XTrack.start_run(
  command: "python",
  args: ["train.py"],
  name: "resnet50_imagenet"
)

# Subscribe for real-time updates
XTrack.subscribe(run_id)

# Handle events in your process
def handle_info({:xtrack_event, :metric, %{key: "val_acc", value: acc}}, state) do
  Logger.info("Validation accuracy: #{Float.round(acc * 100, 2)}%")
  {:noreply, state}
end

def handle_info({:xtrack_event, :checkpoint, %{is_best: true, path: path}}, state) do
  Logger.info("New best checkpoint: #{path}")
  {:noreply, state}
end

def handle_info({:xtrack_event, :run_end, %{status: :completed}}, state) do
  Logger.info("Training complete!")
  {:noreply, state}
end
```

---

## Workflow 2: Hyperparameter Sweep

Run multiple experiments varying hyperparameters.

### Pattern A: Sequential (Simple)

```elixir
defmodule HyperparamSweep do
  def run_sweep do
    learning_rates = [0.001, 0.01, 0.1]
    batch_sizes = [16, 32, 64]
    
    experiment_id = "lr_batch_sweep_#{System.system_time(:second)}"
    
    for lr <- learning_rates, bs <- batch_sizes do
      {:ok, run_id} = XTrack.start_run(
        command: "python",
        args: ["train.py"],
        env: [
          {"LR", to_string(lr)},
          {"BATCH_SIZE", to_string(bs)}
        ],
        name: "lr=#{lr}_bs=#{bs}",
        experiment_id: experiment_id,
        tags: %{"lr" => to_string(lr), "batch_size" => to_string(bs)}
      )
      
      # Wait for completion
      wait_for_run(run_id)
    end
    
    # Analyze results
    analyze_experiment(experiment_id)
  end
  
  defp wait_for_run(run_id) do
    receive do
      {:xtrack_event, :run_end, _} -> :ok
    after
      3_600_000 -> {:error, :timeout}
    end
  end
end
```

### Pattern B: Parallel (Task.async_stream)

```elixir
defmodule ParallelSweep do
  def run_sweep(param_grid, opts \\ []) do
    max_parallel = Keyword.get(opts, :max_parallel, 4)
    experiment_id = Keyword.get(opts, :experiment_id, generate_id())
    
    # Generate all combinations
    combinations = cartesian_product(param_grid)
    
    # Run in parallel
    combinations
    |> Task.async_stream(
      fn params -> run_single(params, experiment_id) end,
      max_concurrency: max_parallel,
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end
  
  defp run_single(params, experiment_id) do
    {:ok, run_id} = XTrack.start_run(
      command: "python",
      args: ["train.py"],
      env: Enum.map(params, fn {k, v} -> {String.upcase(to_string(k)), to_string(v)} end),
      experiment_id: experiment_id,
      tags: Map.new(params, fn {k, v} -> {to_string(k), to_string(v)} end)
    )
    
    XTrack.subscribe(run_id)
    wait_for_completion(run_id)
    run_id
  end
end
```

### Pattern C: External Orchestration (Pool-based)

When workers are managed externally (GPU cluster, Kubernetes):

```elixir
defmodule ClusterSweep do
  def run_sweep(param_grid, opts) do
    experiment_id = generate_id()
    
    # Start TCP server
    {:ok, _} = XTrack.start_tcp_server(port: 9999)
    
    # Submit jobs to external scheduler
    for params <- cartesian_product(param_grid) do
      run_id = generate_run_id()
      
      # Start collector before job
      {:ok, _} = XTrack.start_collector(run_id)
      
      # Submit to SLURM/K8s/etc
      submit_job(%{
        script: "train.py",
        env: %{
          "XTRACK_TRANSPORT" => "tcp",
          "XTRACK_HOST" => node_ip(),
          "XTRACK_PORT" => "9999",
          "XTRACK_RUN_ID" => run_id
        } |> Map.merge(params_to_env(params))
      })
      
      run_id
    end
  end
end
```

---

## Workflow 3: Real-time Dashboard

Build a LiveView dashboard showing training progress.

### LiveView Module

```elixir
defmodule MyAppWeb.ExperimentLive do
  use MyAppWeb, :live_view
  
  def mount(%{"run_id" => run_id}, _session, socket) do
    if connected?(socket) do
      XTrack.subscribe(run_id)
    end
    
    {:ok, run} = XTrack.get_run(run_id)
    
    {:ok, assign(socket,
      run_id: run_id,
      run: run,
      loss_history: [],
      latest_metrics: %{},
      status: run.status
    )}
  end
  
  # Handle metric events
  def handle_info({:xtrack_event, :metric, %{key: "loss"} = m}, socket) do
    history = [{m.step, m.value} | socket.assigns.loss_history] |> Enum.take(1000)
    {:noreply, assign(socket, loss_history: history)}
  end
  
  def handle_info({:xtrack_event, :metric_batch, %{metrics: metrics}}, socket) do
    latest = Map.merge(socket.assigns.latest_metrics, metrics)
    {:noreply, assign(socket, latest_metrics: latest)}
  end
  
  # Handle status changes
  def handle_info({:xtrack_event, :status, %{status: status, progress: progress}}, socket) do
    {:noreply, assign(socket, status: status, progress: progress)}
  end
  
  # Handle completion
  def handle_info({:xtrack_event, :run_end, %{status: status}}, socket) do
    {:ok, run} = XTrack.get_run(socket.assigns.run_id)
    {:noreply, assign(socket, run: run, status: status)}
  end
  
  # Ignore other events
  def handle_info({:xtrack_event, _, _}, socket), do: {:noreply, socket}
  
  def render(assigns) do
    ~H"""
    <div class="dashboard">
      <header>
        <h1><%= @run.name %></h1>
        <.status_badge status={@status} />
      </header>
      
      <.progress_bar :if={@progress} progress={@progress} />
      
      <div class="metrics-grid">
        <.metric_card :for={{key, value} <- @latest_metrics} key={key} value={value} />
      </div>
      
      <.loss_chart data={@loss_history} />
      
      <.params_table params={@run.params} />
    </div>
    """
  end
end
```

### Chart Component (with JS Hook)

```javascript
// assets/js/hooks/loss_chart.js
export const LossChart = {
  mounted() {
    this.chart = new Chart(this.el, {
      type: 'line',
      data: { datasets: [{ data: [] }] }
    })
  },
  
  updated() {
    const data = JSON.parse(this.el.dataset.points)
    this.chart.data.datasets[0].data = data.map(([x, y]) => ({x, y}))
    this.chart.update('none')
  }
}
```

---

## Workflow 4: Experiment Comparison

Compare metrics across multiple runs.

### Query Pattern

```elixir
defmodule ExperimentAnalysis do
  def compare_runs(experiment_id) do
    {:ok, runs} = XTrack.search_runs(experiment_id: experiment_id)
    
    # Get final metrics for each run
    runs_with_metrics = Enum.map(runs, fn run ->
      {:ok, metrics} = XTrack.get_metrics(run.run_id, "val_loss")
      {:ok, params} = XTrack.get_params(run.run_id)
      
      final_loss = metrics |> List.first() |> Map.get(:value)
      
      %{
        run_id: run.run_id,
        name: run.name,
        params: params,
        final_val_loss: final_loss,
        duration_ms: run.duration_ms
      }
    end)
    
    # Sort by performance
    Enum.sort_by(runs_with_metrics, & &1.final_val_loss)
  end
  
  def best_run(experiment_id) do
    experiment_id
    |> compare_runs()
    |> List.first()
  end
  
  def param_sensitivity(experiment_id, param_key) do
    {:ok, runs} = XTrack.search_runs(experiment_id: experiment_id)
    
    runs
    |> Enum.group_by(fn run ->
      {:ok, params} = XTrack.get_params(run.run_id)
      params[param_key]
    end)
    |> Enum.map(fn {value, group} ->
      losses = Enum.map(group, fn run ->
        {:ok, metrics} = XTrack.get_metrics(run.run_id, "val_loss")
        metrics |> List.first() |> Map.get(:value)
      end)
      
      {value, Enum.sum(losses) / length(losses)}
    end)
    |> Enum.sort_by(fn {_, avg} -> avg end)
  end
end
```

---

## Workflow 5: Model Registry

Promote best models to a registry.

### Registry Pattern

```elixir
defmodule ModelRegistry do
  @stages [:development, :staging, :production]
  
  def register_model(run_id, name, opts \\ []) do
    {:ok, run} = XTrack.get_run(run_id)
    
    # Find best checkpoint
    best_checkpoint = Enum.find(run.checkpoints, & &1.is_best)
    
    model = %{
      name: name,
      version: next_version(name),
      run_id: run_id,
      artifact_path: best_checkpoint.path,
      metrics: best_checkpoint.metrics_snapshot,
      stage: :development,
      created_at: DateTime.utc_now()
    }
    
    # Store in registry (your DB)
    save_model(model)
    
    # Broadcast for interested services
    Phoenix.PubSub.broadcast(XTrack.PubSub, "models:#{name}", {:model_registered, model})
    
    {:ok, model}
  end
  
  def promote(name, version, to_stage) when to_stage in @stages do
    model = get_model(name, version)
    
    # Validate promotion rules
    case {model.stage, to_stage} do
      {:development, :staging} -> :ok
      {:staging, :production} -> :ok
      _ -> {:error, :invalid_promotion}
    end
    
    updated = %{model | stage: to_stage}
    save_model(updated)
    
    # Notify serving infrastructure
    Phoenix.PubSub.broadcast(XTrack.PubSub, "models:#{name}", {:model_promoted, updated})
    
    {:ok, updated}
  end
  
  def get_production_model(name) do
    list_models(name)
    |> Enum.find(& &1.stage == :production)
  end
end
```

### Serving Integration

```elixir
defmodule ModelServer do
  use GenServer
  
  def start_link(model_name) do
    GenServer.start_link(__MODULE__, model_name, name: via(model_name))
  end
  
  def init(model_name) do
    # Subscribe to model updates
    Phoenix.PubSub.subscribe(XTrack.PubSub, "models:#{model_name}")
    
    # Load current production model
    model = ModelRegistry.get_production_model(model_name)
    serving = load_model(model)
    
    {:ok, %{model_name: model_name, serving: serving, current_model: model}}
  end
  
  # Hot-reload on promotion
  def handle_info({:model_promoted, %{stage: :production} = model}, state) do
    Logger.info("Loading new production model: #{model.name} v#{model.version}")
    
    new_serving = load_model(model)
    
    {:noreply, %{state | serving: new_serving, current_model: model}}
  end
  
  def handle_info({:model_promoted, _}, state), do: {:noreply, state}
  
  # Inference
  def handle_call({:predict, input}, _from, state) do
    result = Nx.Serving.batched_run(state.serving, input)
    {:reply, result, state}
  end
end
```

---

## Workflow 6: Failure Recovery

Handle crashes and resume training.

### Checkpoint-based Recovery

```python
from xtrack import Tracker
import os

def train_with_recovery():
    # Check for existing run to resume
    resume_run_id = os.environ.get("XTRACK_RESUME_RUN_ID")
    resume_checkpoint = os.environ.get("XTRACK_RESUME_CHECKPOINT")
    
    if resume_run_id and resume_checkpoint:
        # Resume existing run
        run = Tracker.start_run(run_id=resume_run_id, name="resumed")
        model, optimizer, start_epoch = load_checkpoint(resume_checkpoint)
        run.log("Resumed from checkpoint", checkpoint=resume_checkpoint, epoch=start_epoch)
    else:
        # Fresh run
        run = Tracker.start_run(name="training")
        model, optimizer = create_model()
        start_epoch = 0
    
    with run:
        for epoch in range(start_epoch, 100):
            train_loss = train_epoch(model, optimizer)
            run.log_metric("train_loss", train_loss, epoch=epoch)
            
            # Checkpoint every epoch
            path = f"checkpoint_{epoch}.pt"
            save_checkpoint(model, optimizer, epoch, path)
            run.log_checkpoint(path, step=epoch)
```

### Elixir Recovery Logic

```elixir
defmodule TrainingManager do
  use GenServer
  
  def start_training(config) do
    GenServer.call(__MODULE__, {:start, config})
  end
  
  def handle_call({:start, config}, _from, state) do
    {:ok, run_id} = XTrack.start_run(config)
    XTrack.subscribe(run_id)
    
    # Track active run
    state = Map.put(state, :active_run, %{
      run_id: run_id,
      config: config,
      last_checkpoint: nil
    })
    
    {:reply, {:ok, run_id}, state}
  end
  
  # Track checkpoints
  def handle_info({:xtrack_event, :checkpoint, ckpt}, state) do
    state = put_in(state, [:active_run, :last_checkpoint], ckpt)
    {:noreply, state}
  end
  
  # Handle crash
  def handle_info({:xtrack_event, :run_end, %{status: :failed}}, state) do
    active = state.active_run
    
    if active.last_checkpoint do
      Logger.info("Run failed, attempting recovery from #{active.last_checkpoint.path}")
      
      # Restart with resume config
      resume_config = active.config
      |> Keyword.put(:env, [
        {"XTRACK_RESUME_RUN_ID", active.run_id},
        {"XTRACK_RESUME_CHECKPOINT", active.last_checkpoint.path}
        | Keyword.get(active.config, :env, [])
      ])
      
      {:ok, new_run_id} = XTrack.start_run(resume_config)
      
      state = put_in(state, [:active_run, :run_id], new_run_id)
      {:noreply, state}
    else
      Logger.error("Run failed with no checkpoint, cannot recover")
      {:noreply, %{state | active_run: nil}}
    end
  end
end
```

---

## Workflow 7: Distributed Training

Track multi-worker training jobs.

### Worker Setup

```python
# Each worker has unique XTRACK_WORKER_ID
import os
from xtrack import Tracker

worker_id = os.environ["XTRACK_WORKER_ID"]  # "worker-0", "worker-1", etc
world_size = int(os.environ["WORLD_SIZE"])

with Tracker.start_run(name=f"distributed_training") as run:
    run.log_params({
        "world_size": world_size,
        "worker_id": worker_id
    })
    
    for step in range(1000):
        loss = train_step(model)
        
        # Each worker logs with its worker_id in metadata
        run.log_metric("loss", loss, step=step)
        
        # Only rank 0 does checkpointing
        if worker_id == "worker-0" and step % 100 == 0:
            run.log_checkpoint(f"ckpt_{step}.pt", step=step)
```

### Collector Aggregation

The collector receives events from all workers, distinguished by `worker_id` in metadata:

```elixir
defmodule DistributedCollector do
  # Events arrive with worker_id in metadata
  def handle_event(%Envelope{meta: %{worker_id: wid}, payload: %Metric{} = m}, state) do
    # Store per-worker metrics
    key = "#{m.key}:#{wid}"
    state = update_in(state.metrics[key], &[m | (&1 || [])])
    
    # Also compute aggregate
    if all_workers_reported?(state, m.step) do
      avg = compute_average(state, m.key, m.step)
      broadcast_aggregate(state.run_id, m.key, avg, m.step)
    end
    
    {:ok, state}
  end
end
```

---

## Anti-Patterns

### ❌ Logging Too Frequently

```python
# BAD: Logs every iteration
for i, batch in enumerate(dataloader):
    loss = train_step(batch)
    run.log_metric("loss", loss, step=i)  # 10000s of events per epoch
```

```python
# GOOD: Log periodically
for i, batch in enumerate(dataloader):
    loss = train_step(batch)
    if i % 100 == 0:
        run.log_metric("loss", loss, step=i)
```

### ❌ Blocking on Tracking

```python
# BAD: Synchronous artifact upload
run.log_artifact("huge_model.pt")  # Blocks training
```

```python
# GOOD: Reference only, handle upload separately
run.log_artifact("huge_model.pt", upload_strategy="reference")
```

### ❌ Not Using Batched Metrics

```python
# BAD: Multiple events for same step
run.log_metric("loss", loss, step=step)
run.log_metric("acc", acc, step=step)
run.log_metric("lr", lr, step=step)
```

```python
# GOOD: Single atomic event
run.log_metrics({"loss": loss, "acc": acc, "lr": lr}, step=step)
```

### ❌ Ignoring Run Failures

```elixir
# BAD: No error handling
{:ok, run_id} = XTrack.start_run(config)
# ... never checks if run completed
```

```elixir
# GOOD: Handle all outcomes
XTrack.subscribe(run_id)

receive do
  {:xtrack_event, :run_end, %{status: :completed}} -> :ok
  {:xtrack_event, :run_end, %{status: :failed, error: e}} -> handle_failure(e)
after
  timeout -> handle_timeout()
end
```
