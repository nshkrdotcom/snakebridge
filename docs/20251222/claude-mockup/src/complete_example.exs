# XTrack End-to-End Example
#
# This shows the complete flow of tracking a PyTorch training job from Elixir.

# ============================================================================
# 1. Python Training Script (train.py)
# ============================================================================
#
# This would be saved as train.py:
#
# ```python
# """Example PyTorch training script with XTrack integration."""
# 
# import torch
# import torch.nn as nn
# import torch.optim as optim
# from torch.utils.data import DataLoader, TensorDataset
# from xtrack import Tracker, PyTorchCallback
# 
# # Simple model
# class SimpleNet(nn.Module):
#     def __init__(self, input_dim, hidden_dim, output_dim):
#         super().__init__()
#         self.fc1 = nn.Linear(input_dim, hidden_dim)
#         self.fc2 = nn.Linear(hidden_dim, output_dim)
#         self.relu = nn.ReLU()
#     
#     def forward(self, x):
#         x = self.relu(self.fc1(x))
#         return self.fc2(x)
# 
# def main():
#     # Hyperparameters (could come from env or args)
#     import os
#     lr = float(os.environ.get('LR', '0.001'))
#     batch_size = int(os.environ.get('BATCH_SIZE', '32'))
#     epochs = int(os.environ.get('EPOCHS', '10'))
#     hidden_dim = int(os.environ.get('HIDDEN_DIM', '64'))
#     
#     # Start tracking
#     with Tracker.start_run(name="pytorch_example") as run:
#         # Log hyperparameters
#         run.log_params({
#             "learning_rate": lr,
#             "batch_size": batch_size,
#             "epochs": epochs,
#             "hidden_dim": hidden_dim,
#             "optimizer": "adam"
#         })
#         
#         # Create callback for automatic logging
#         callback = PyTorchCallback(run, log_every_n_steps=10)
#         
#         # Fake data for demo
#         X = torch.randn(1000, 10)
#         y = torch.randn(1000, 1)
#         dataset = TensorDataset(X, y)
#         loader = DataLoader(dataset, batch_size=batch_size, shuffle=True)
#         
#         # Model, loss, optimizer
#         model = SimpleNet(10, hidden_dim, 1)
#         criterion = nn.MSELoss()
#         optimizer = optim.Adam(model.parameters(), lr=lr)
#         
#         run.set_status("training")
#         best_loss = float('inf')
#         
#         for epoch in range(epochs):
#             callback.on_epoch_start(epoch, epochs)
#             
#             epoch_loss = 0.0
#             for step, (batch_x, batch_y) in enumerate(loader):
#                 optimizer.zero_grad()
#                 pred = model(batch_x)
#                 loss = criterion(pred, batch_y)
#                 loss.backward()
#                 optimizer.step()
#                 
#                 epoch_loss += loss.item()
#                 callback.on_step_end(epoch * len(loader) + step, {"loss": loss.item()})
#             
#             avg_loss = epoch_loss / len(loader)
#             
#             # Validation (using same data for demo)
#             model.eval()
#             with torch.no_grad():
#                 val_pred = model(X)
#                 val_loss = criterion(val_pred, y).item()
#             model.train()
#             
#             # Log epoch metrics
#             callback.on_epoch_end(epoch, {
#                 "train_loss": avg_loss,
#                 "val_loss": val_loss
#             })
#             
#             # Checkpoint
#             is_best = val_loss < best_loss
#             if is_best:
#                 best_loss = val_loss
#             
#             checkpoint_path = f"checkpoint_epoch_{epoch}.pt"
#             torch.save({
#                 'epoch': epoch,
#                 'model_state_dict': model.state_dict(),
#                 'optimizer_state_dict': optimizer.state_dict(),
#                 'loss': val_loss,
#             }, checkpoint_path)
#             
#             callback.on_checkpoint(
#                 checkpoint_path,
#                 {"val_loss": val_loss},
#                 is_best=is_best,
#                 best_metric="val_loss"
#             )
#         
#         # Log final model
#         final_path = "model_final.pt"
#         torch.save(model.state_dict(), final_path)
#         run.log_artifact(final_path, artifact_type="model")
#         
#         run.log("Training complete", level="info", final_loss=val_loss)
# 
# if __name__ == "__main__":
#     main()
# ```

# ============================================================================
# 2. Elixir: Basic Usage
# ============================================================================

defmodule XTrack.Examples.Basic do
  @moduledoc "Basic XTrack usage examples"

  @doc """
  Start a single training run and monitor it.
  """
  def run_single_experiment do
    # Start XTrack
    {:ok, _} = XTrack.start()

    # Subscribe to events before starting
    run_id = "demo-run-#{System.unique_integer([:positive])}"
    XTrack.subscribe(run_id)

    # Start the training job
    {:ok, ^run_id} =
      XTrack.start_run(
        run_id: run_id,
        command: "python",
        args: ["train.py"],
        env: [
          {"LR", "0.001"},
          {"EPOCHS", "5"},
          {"BATCH_SIZE", "32"}
        ],
        name: "demo_training",
        experiment_id: "basic_examples",
        tags: %{"type" => "demo"}
      )

    # Monitor events
    monitor_loop(run_id)
  end

  defp monitor_loop(run_id) do
    receive do
      {:xtrack_event, :metric, %{key: key, value: value, step: step}} ->
        IO.puts("[Metric] #{key}=#{Float.round(value, 4)} (step=#{step})")
        monitor_loop(run_id)

      {:xtrack_event, :metric_batch, %{metrics: metrics, epoch: epoch}} ->
        metrics_str =
          metrics |> Enum.map(fn {k, v} -> "#{k}=#{Float.round(v, 4)}" end) |> Enum.join(", ")

        IO.puts("[Epoch #{epoch}] #{metrics_str}")
        monitor_loop(run_id)

      {:xtrack_event, :checkpoint, %{path: path, is_best: is_best}} ->
        best_str = if is_best, do: " [BEST]", else: ""
        IO.puts("[Checkpoint] #{path}#{best_str}")
        monitor_loop(run_id)

      {:xtrack_event, :status, %{status: status, message: msg}} ->
        IO.puts("[Status] #{status}: #{msg}")
        monitor_loop(run_id)

      {:xtrack_event, :run_end, %{status: status, duration_ms: duration}} ->
        IO.puts("[Complete] Status: #{status}, Duration: #{duration}ms")

        # Print summary
        print_run_summary(run_id)

      {:xtrack_event, event_type, _payload} ->
        IO.puts("[Event] #{event_type}")
        monitor_loop(run_id)
    after
      60_000 ->
        IO.puts("[Timeout] No events for 60 seconds")
    end
  end

  defp print_run_summary(run_id) do
    {:ok, run} = XTrack.get_run(run_id)

    IO.puts("\n=== Run Summary ===")
    IO.puts("Run ID: #{run_id}")
    IO.puts("Name: #{run.name}")
    IO.puts("Status: #{run.status}")

    IO.puts("\nParameters:")
    Enum.each(run.params, fn {k, v} -> IO.puts("  #{k}: #{inspect(v)}") end)

    IO.puts("\nFinal Metrics:")

    Enum.each(run.metrics, fn {key, points} ->
      latest = List.first(points)
      if latest, do: IO.puts("  #{key}: #{Float.round(latest.value, 4)}")
    end)

    IO.puts("\nCheckpoints: #{length(run.checkpoints)}")
    IO.puts("Artifacts: #{length(run.artifacts)}")
  end
end

# ============================================================================
# 3. Elixir: Grid Search with Snakepit
# ============================================================================

defmodule XTrack.Examples.GridSearch do
  @moduledoc "Hyperparameter grid search example"

  @doc """
  Run a learning rate and batch size sweep.
  """
  def run_lr_sweep do
    # Start XTrack
    {:ok, _} = XTrack.start()

    # Start TCP server for workers
    {:ok, _} = XTrack.start_tcp_server(port: 9999)

    # Configure Snakepit pool (assumes Snakepit is available)
    # In practice, you'd configure this based on your GPU setup
    pool_config = %{
      # 4 parallel workers
      pool_size: 4,
      python_path: "/usr/bin/python",
      startup_script: XTrack.Snakepit.worker_script(),
      env: [
        {"XTRACK_TRANSPORT", "tcp"},
        {"XTRACK_HOST", "localhost"},
        {"XTRACK_PORT", "9999"}
      ]
    }

    # This would start the actual pool
    # {:ok, pool} = Snakepit.start_pool(pool_config)

    # For demo, we'll just show the structure
    IO.puts("Would start grid search with config:")
    IO.inspect(pool_config)

    experiment_id = "lr_batch_sweep_#{System.system_time(:second)}"

    param_grid = %{
      lr: [0.0001, 0.001, 0.01, 0.1],
      batch_size: [16, 32, 64],
      hidden_dim: [32, 64, 128]
    }

    total_runs = 4 * 3 * 3
    IO.puts("\nGrid search: #{total_runs} runs across #{map_size(param_grid)} parameters")
    IO.puts("Experiment ID: #{experiment_id}")

    # In practice:
    # {:ok, run_ids} = XTrack.Snakepit.grid_search(pool, %{
    #   script: "train.py",
    #   param_grid: param_grid,
    #   experiment_id: experiment_id,
    #   max_parallel: 4
    # })
    #
    # Then analyze results:
    # analyze_experiment(experiment_id)
  end

  @doc """
  Analyze results of a completed experiment.
  """
  def analyze_experiment(experiment_id) do
    {:ok, runs} = XTrack.search_runs(experiment_id: experiment_id)

    IO.puts("\n=== Experiment Analysis ===")
    IO.puts("Experiment: #{experiment_id}")
    IO.puts("Total runs: #{length(runs)}")

    # Get best run by validation loss
    runs_with_metrics =
      Enum.map(runs, fn run ->
        {:ok, metrics} = XTrack.get_metrics(run.run_id, "val_loss")
        best_val_loss = metrics |> Enum.map(& &1.value) |> Enum.min(fn -> nil end)
        {:ok, params} = XTrack.get_params(run.run_id)

        %{
          run_id: run.run_id,
          params: params,
          best_val_loss: best_val_loss
        }
      end)

    best_run = Enum.min_by(runs_with_metrics, & &1.best_val_loss, fn -> nil end)

    if best_run do
      IO.puts("\nBest run: #{best_run.run_id}")
      IO.puts("Best val_loss: #{best_run.best_val_loss}")
      IO.puts("Parameters:")
      Enum.each(best_run.params, fn {k, v} -> IO.puts("  #{k}: #{inspect(v)}") end)
    end

    # Parameter importance (simple analysis)
    IO.puts("\nParameter sensitivity:")

    for {param, values} <- group_by_param(runs_with_metrics) do
      IO.puts("  #{param}:")

      for {value, avg_loss} <- values do
        IO.puts("    #{value}: avg_loss=#{Float.round(avg_loss, 4)}")
      end
    end
  end

  defp group_by_param(runs) do
    # Group runs by each parameter value and compute average loss
    params = runs |> List.first() |> Map.get(:params, %{}) |> Map.keys()

    for param <- params, into: %{} do
      grouped = Enum.group_by(runs, &get_in(&1, [:params, param]))

      averages =
        for {value, group} <- grouped do
          avg =
            group
            |> Enum.map(& &1.best_val_loss)
            |> Enum.reject(&is_nil/1)
            |> then(fn losses ->
              if Enum.empty?(losses), do: nil, else: Enum.sum(losses) / length(losses)
            end)

          {value, avg}
        end
        |> Enum.reject(fn {_, avg} -> is_nil(avg) end)
        |> Enum.sort_by(fn {_, avg} -> avg end)

      {param, averages}
    end
  end
end

# ============================================================================
# 4. Elixir: LiveView Dashboard Integration
# ============================================================================

defmodule XTrack.Examples.LiveViewDashboard do
  @moduledoc """
  Example LiveView component for real-time experiment monitoring.

  This shows how to build a dashboard that displays live training progress.
  """

  # This would be a real LiveView in your Phoenix app
  @doc """
  Example LiveView that monitors an experiment in real-time.

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
        metrics_history: %{},
        latest_metrics: %{}
      )}
    end
    
    def handle_info({:xtrack_event, :metric, metric}, socket) do
      # Update metrics history for charts
      history = Map.update(
        socket.assigns.metrics_history,
        metric.key,
        [metric],
        &[metric | Enum.take(&1, 999)]
      )
      
      {:noreply, assign(socket,
        metrics_history: history,
        latest_metrics: Map.put(socket.assigns.latest_metrics, metric.key, metric.value)
      )}
    end
    
    def handle_info({:xtrack_event, :metric_batch, batch}, socket) do
      latest = Map.merge(socket.assigns.latest_metrics, batch.metrics)
      {:noreply, assign(socket, latest_metrics: latest)}
    end
    
    def handle_info({:xtrack_event, :status, status}, socket) do
      run = Map.put(socket.assigns.run, :status, status.status)
      {:noreply, assign(socket, run: run)}
    end
    
    def handle_info({:xtrack_event, :run_end, _}, socket) do
      {:ok, run} = XTrack.get_run(socket.assigns.run_id)
      {:noreply, assign(socket, run: run)}
    end
    
    def handle_info({:xtrack_event, _, _}, socket) do
      {:noreply, socket}
    end
    
    def render(assigns) do
      ~H\"\"\"
      <div class="experiment-dashboard">
        <h1><%= @run.name %></h1>
        <div class="status-badge status-{@run.status}">
          <%= @run.status %>
        </div>
        
        <div class="metrics-grid">
          <%= for {key, value} <- @latest_metrics do %>
            <div class="metric-card">
              <span class="metric-key"><%= key %></span>
              <span class="metric-value"><%= Float.round(value, 4) %></span>
            </div>
          <% end %>
        </div>
        
        <div class="charts">
          <%= for {key, history} <- @metrics_history do %>
            <div class="chart" id={"chart-" <> key} 
                 phx-hook="MetricChart" 
                 data-metric={key}
                 data-points={Jason.encode!(Enum.reverse(history))}>
            </div>
          <% end %>
        </div>
        
        <div class="params">
          <h3>Parameters</h3>
          <%= for {key, value} <- @run.params do %>
            <div><strong><%= key %>:</strong> <%= inspect(value) %></div>
          <% end %>
        </div>
      </div>
      \"\"\"
    end
  end
  ```
  """
  def example_code, do: :see_moduledoc
end

# ============================================================================
# 5. Integration with FlowStone (Your DAG Orchestrator)
# ============================================================================

defmodule XTrack.Examples.FlowStoneIntegration do
  @moduledoc """
  Example of integrating XTrack with FlowStone for ML pipelines.

  This shows how to build a complete ML pipeline:
  1. Data preparation
  2. Training (tracked with XTrack)
  3. Evaluation
  4. Model registration
  """

  @doc """
  Define a training pipeline as a FlowStone DAG.

  ```elixir
  defmodule MyPipeline do
    use FlowStone.Pipeline
    
    asset :raw_data do
      # Load raw data
      load_from_source()
    end
    
    asset :processed_data, deps: [:raw_data] do
      # Preprocess
      preprocess(raw_data)
    end
    
    asset :trained_model, deps: [:processed_data] do
      # Train with XTrack
      {:ok, run_id} = XTrack.start_run(
        command: "python",
        args: ["train.py", "--data", processed_data.path],
        name: "pipeline_training",
        tags: %{"pipeline" => "my_pipeline"}
      )
      
      # Wait for completion
      wait_for_run(run_id)
      
      # Get best checkpoint
      {:ok, run} = XTrack.get_run(run_id)
      best_checkpoint = Enum.find(run.checkpoints, & &1.is_best)
      
      %{run_id: run_id, model_path: best_checkpoint.path}
    end
    
    asset :evaluation, deps: [:trained_model, :processed_data] do
      # Evaluate model
      evaluate(trained_model.model_path, processed_data.test_path)
    end
    
    asset :registered_model, deps: [:trained_model, :evaluation] do
      if evaluation.metrics.accuracy > 0.9 do
        # Register in model registry
        register_model(trained_model.model_path, 
          name: "my_model",
          version: next_version(),
          metrics: evaluation.metrics
        )
      else
        :skip
      end
    end
  end
  ```
  """
  def example_pipeline, do: :see_moduledoc
end
