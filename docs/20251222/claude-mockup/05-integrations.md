# XTrack Integration Guide

This document covers integrating XTrack with various systems and frameworks.

---

## Python Framework Integrations

### PyTorch

XTrack provides a callback class for PyTorch training loops:

```python
from xtrack import Tracker, PyTorchCallback

with Tracker.start_run(name="pytorch_training") as run:
    run.log_params({"lr": 0.001, "epochs": 10})
    
    callback = PyTorchCallback(run, log_every_n_steps=100)
    
    for epoch in range(10):
        callback.on_epoch_start(epoch, total_epochs=10)
        
        for step, batch in enumerate(train_loader):
            loss = train_step(model, batch, optimizer)
            callback.on_step_end(step, {"loss": loss.item()})
        
        val_metrics = validate(model, val_loader)
        callback.on_epoch_end(epoch, val_metrics)
        
        # Checkpoint
        save_checkpoint(model, f"ckpt_{epoch}.pt")
        callback.on_checkpoint(
            f"ckpt_{epoch}.pt",
            metrics=val_metrics,
            is_best=val_metrics["val_loss"] < best_loss
        )
```

### PyTorch Lightning

Create a custom callback:

```python
import pytorch_lightning as pl
from xtrack import Tracker

class XTrackCallback(pl.Callback):
    def __init__(self, run_name=None):
        self.run = None
        self.run_name = run_name
    
    def on_fit_start(self, trainer, pl_module):
        self.run = Tracker.start_run(name=self.run_name)
        self.run.log_params(dict(trainer.hparams))
    
    def on_train_batch_end(self, trainer, pl_module, outputs, batch, batch_idx):
        if batch_idx % 100 == 0:
            self.run.log_metrics(
                {"train_loss": outputs["loss"].item()},
                step=trainer.global_step
            )
    
    def on_validation_end(self, trainer, pl_module):
        metrics = {k: v.item() for k, v in trainer.callback_metrics.items()}
        self.run.log_metrics(metrics, epoch=trainer.current_epoch)
    
    def on_fit_end(self, trainer, pl_module):
        self.run.end()

# Usage
trainer = pl.Trainer(callbacks=[XTrackCallback("lightning_run")])
```

### Hugging Face Transformers

Custom callback for the Trainer:

```python
from transformers import TrainerCallback
from xtrack import Tracker

class XTrackHFCallback(TrainerCallback):
    def __init__(self, run_name=None):
        self.run = None
        self.run_name = run_name
    
    def on_train_begin(self, args, state, control, **kwargs):
        self.run = Tracker.start_run(name=self.run_name)
        self.run.log_params({
            "learning_rate": args.learning_rate,
            "batch_size": args.per_device_train_batch_size,
            "epochs": args.num_train_epochs,
            "model": kwargs.get("model").__class__.__name__
        })
    
    def on_log(self, args, state, control, logs=None, **kwargs):
        if logs:
            self.run.log_metrics(logs, step=state.global_step)
    
    def on_save(self, args, state, control, **kwargs):
        self.run.log_checkpoint(
            args.output_dir,
            step=state.global_step,
            is_best=state.best_model_checkpoint == args.output_dir
        )
    
    def on_train_end(self, args, state, control, **kwargs):
        self.run.end()

# Usage
trainer = Trainer(
    model=model,
    args=training_args,
    callbacks=[XTrackHFCallback("transformers_run")]
)
```

### Keras/TensorFlow

Custom callback for Keras:

```python
import tensorflow as tf
from xtrack import Tracker

class XTrackKerasCallback(tf.keras.callbacks.Callback):
    def __init__(self, run_name=None):
        super().__init__()
        self.run = None
        self.run_name = run_name
    
    def on_train_begin(self, logs=None):
        self.run = Tracker.start_run(name=self.run_name)
        self.run.log_params({
            "optimizer": self.model.optimizer.__class__.__name__,
            "loss": self.model.loss,
        })
    
    def on_epoch_end(self, epoch, logs=None):
        if logs:
            self.run.log_metrics(logs, epoch=epoch)
    
    def on_train_end(self, logs=None):
        self.run.end()

# Usage
model.fit(x, y, callbacks=[XTrackKerasCallback("keras_run")])
```

---

## Elixir Framework Integrations

### Phoenix LiveView

Real-time experiment monitoring:

```elixir
defmodule MyAppWeb.RunLive do
  use MyAppWeb, :live_view
  
  @impl true
  def mount(%{"run_id" => run_id}, _session, socket) do
    if connected?(socket), do: XTrack.subscribe(run_id)
    
    {:ok, run} = XTrack.get_run(run_id)
    {:ok, loss_history} = XTrack.get_metrics(run_id, "loss")
    
    socket = assign(socket,
      run_id: run_id,
      run: run,
      loss_history: format_for_chart(loss_history),
      latest_metrics: %{}
    )
    
    {:ok, socket}
  end
  
  @impl true
  def handle_info({:xtrack_event, :metric, m}, socket) do
    socket = update_metric(socket, m)
    {:noreply, socket}
  end
  
  def handle_info({:xtrack_event, :run_end, _}, socket) do
    {:ok, run} = XTrack.get_run(socket.assigns.run_id)
    {:noreply, assign(socket, run: run)}
  end
  
  def handle_info({:xtrack_event, _, _}, socket), do: {:noreply, socket}
end
```

### Broadway (for batch processing)

Process events from file transport:

```elixir
defmodule XTrackBroadway do
  use Broadway
  
  def start_link(opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {XTrackFileProducer, opts}
      ],
      processors: [
        default: [concurrency: 10]
      ]
    )
  end
  
  @impl true
  def handle_message(_, %Broadway.Message{data: envelope} = message, _) do
    run_id = extract_run_id(envelope)
    XTrack.Collector.push_event(run_id, envelope)
    message
  end
end

defmodule XTrackFileProducer do
  use GenStage
  
  def init(opts) do
    path = Keyword.fetch!(opts, :path)
    stream = XTrack.stream_file(path)
    {:producer, %{stream: stream}}
  end
  
  def handle_demand(demand, state) do
    events = state.stream |> Enum.take(demand)
    {:noreply, events, state}
  end
end
```

### Oban (for background jobs)

Schedule experiment jobs:

```elixir
defmodule MyApp.ExperimentWorker do
  use Oban.Worker, queue: :experiments
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"config" => config}}) do
    {:ok, run_id} = XTrack.start_run(
      command: config["command"],
      args: config["args"],
      name: config["name"]
    )
    
    # Wait for completion
    XTrack.subscribe(run_id)
    
    receive do
      {:xtrack_event, :run_end, %{status: :completed}} ->
        :ok
      {:xtrack_event, :run_end, %{status: :failed, error: e}} ->
        {:error, e}
    after
      :timer.hours(24) ->
        XTrack.stop_run(run_id)
        {:error, :timeout}
    end
  end
end

# Schedule
%{config: %{command: "python", args: ["train.py"], name: "scheduled_run"}}
|> MyApp.ExperimentWorker.new(scheduled_at: ~U[2024-01-01 00:00:00Z])
|> Oban.insert()
```

---

## External System Integrations

### Kubernetes

Deploy XTrack server as a service, workers connect via TCP:

```yaml
# xtrack-server.yaml
apiVersion: v1
kind: Service
metadata:
  name: xtrack-server
spec:
  ports:
    - port: 9999
      targetPort: 9999
  selector:
    app: xtrack-server
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: xtrack-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: xtrack-server
  template:
    spec:
      containers:
        - name: xtrack
          image: your-elixir-app:latest
          ports:
            - containerPort: 9999
          command: ["bin/your_app", "start"]
```

```yaml
# training-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: training-job
spec:
  template:
    spec:
      containers:
        - name: trainer
          image: your-training-image:latest
          env:
            - name: XTRACK_TRANSPORT
              value: "tcp"
            - name: XTRACK_HOST
              value: "xtrack-server"
            - name: XTRACK_PORT
              value: "9999"
            - name: XTRACK_RUN_ID
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
```

### SLURM

Submit jobs with XTrack environment:

```bash
#!/bin/bash
#SBATCH --job-name=training
#SBATCH --nodes=1
#SBATCH --gpus=4

export XTRACK_TRANSPORT=tcp
export XTRACK_HOST=$ELIXIR_SERVER_IP
export XTRACK_PORT=9999
export XTRACK_RUN_ID=$SLURM_JOB_ID

python train.py
```

Elixir side:

```elixir
# Pre-create collectors for expected jobs
def prepare_slurm_job(job_id) do
  XTrack.start_collector(job_id)
end
```

### AWS SageMaker

Custom container with XTrack:

```dockerfile
# Dockerfile
FROM python:3.11
RUN pip install sagemaker-training
COPY xtrack/ /opt/ml/code/xtrack/
COPY train.py /opt/ml/code/

ENV SAGEMAKER_PROGRAM=train.py
ENV XTRACK_TRANSPORT=tcp
```

Training script:

```python
# train.py
import os
from xtrack import Tracker

# SageMaker provides hyperparameters via environment
hyperparameters = {
    "lr": float(os.environ.get("SM_HP_LR", "0.001")),
    "epochs": int(os.environ.get("SM_HP_EPOCHS", "10"))
}

with Tracker.start_run(name="sagemaker_training") as run:
    run.log_params(hyperparameters)
    # ... training code
```

---

## Database Integrations

### PostgreSQL (built-in)

Configure in your Elixir app:

```elixir
# config/config.exs
config :xtrack,
  storage: :postgres,
  repo: MyApp.Repo

# Run migrations
mix ecto.migrate
```

The Postgres backend provides:
- Persistent storage
- SQL queries for complex analysis
- Materialized view for fast metric queries

### ClickHouse (custom backend)

For high-volume time-series:

```elixir
defmodule XTrack.Storage.ClickHouse do
  @behaviour XTrack.Storage
  
  @impl true
  def persist_event(run_id, envelope) do
    Pillar.insert(MyApp.ClickHouse, "xtrack_events", %{
      run_id: run_id,
      seq: envelope.meta.seq,
      event_type: Atom.to_string(envelope.event_type),
      timestamp: envelope.meta.timestamp_us,
      payload: Jason.encode!(envelope.payload)
    })
  end
  
  @impl true
  def get_metrics(run_id, metric_key) do
    query = """
    SELECT step, value, timestamp
    FROM xtrack_metrics
    WHERE run_id = {run_id:String}
      AND metric_key = {key:String}
    ORDER BY step
    """
    
    Pillar.select(MyApp.ClickHouse, query, %{run_id: run_id, key: metric_key})
  end
end
```

### S3 (artifact storage)

Store artifacts in S3:

```elixir
defmodule XTrack.ArtifactStore.S3 do
  def upload_artifact(run_id, %Artifact{} = artifact) do
    key = "runs/#{run_id}/artifacts/#{Path.basename(artifact.path)}"
    
    artifact.path
    |> File.read!()
    |> ExAws.S3.put_object("xtrack-artifacts", key)
    |> ExAws.request!()
    
    %{artifact | path: "s3://xtrack-artifacts/#{key}"}
  end
  
  def download_artifact(s3_path) do
    %{bucket: bucket, key: key} = parse_s3_url(s3_path)
    
    ExAws.S3.get_object(bucket, key)
    |> ExAws.request!()
    |> Map.get(:body)
  end
end
```

---

## Monitoring Integrations

### Prometheus

Export metrics for Prometheus scraping:

```elixir
defmodule XTrack.PrometheusExporter do
  use Prometheus.PlugExporter
  
  def setup do
    Gauge.declare(
      name: :xtrack_active_runs,
      help: "Number of active experiment runs"
    )
    
    Counter.declare(
      name: :xtrack_events_total,
      labels: [:event_type],
      help: "Total events received"
    )
    
    Histogram.declare(
      name: :xtrack_metric_value,
      labels: [:run_id, :metric_key],
      help: "Metric values"
    )
  end
  
  def record_event(envelope) do
    Counter.inc(
      name: :xtrack_events_total,
      labels: [envelope.event_type]
    )
    
    case envelope do
      %{event_type: :metric, payload: m} ->
        Histogram.observe(
          [name: :xtrack_metric_value, labels: [m.run_id, m.key]],
          m.value
        )
      _ ->
        :ok
    end
  end
end
```

### Grafana

Dashboard JSON for XTrack metrics:

```json
{
  "title": "XTrack Experiments",
  "panels": [
    {
      "title": "Active Runs",
      "type": "stat",
      "targets": [
        {"expr": "xtrack_active_runs"}
      ]
    },
    {
      "title": "Events per Second",
      "type": "graph",
      "targets": [
        {"expr": "rate(xtrack_events_total[1m])"}
      ]
    },
    {
      "title": "Training Loss",
      "type": "graph",
      "targets": [
        {"expr": "xtrack_metric_value{metric_key=\"loss\"}"}
      ]
    }
  ]
}
```

---

## Message Queue Integrations

### RabbitMQ

Publish events to RabbitMQ for external consumers:

```elixir
defmodule XTrack.RabbitMQPublisher do
  use GenServer
  use AMQP
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    {:ok, conn} = Connection.open("amqp://localhost")
    {:ok, chan} = Channel.open(conn)
    
    Exchange.declare(chan, "xtrack_events", :topic)
    
    {:ok, %{channel: chan}}
  end
  
  def publish_event(run_id, envelope) do
    GenServer.cast(__MODULE__, {:publish, run_id, envelope})
  end
  
  def handle_cast({:publish, run_id, envelope}, state) do
    routing_key = "run.#{run_id}.#{envelope.event_type}"
    payload = Jason.encode!(envelope)
    
    Basic.publish(state.channel, "xtrack_events", routing_key, payload)
    
    {:noreply, state}
  end
end
```

### Kafka

Stream events to Kafka:

```elixir
defmodule XTrack.KafkaProducer do
  def publish_event(run_id, envelope) do
    message = %{
      key: run_id,
      value: Jason.encode!(envelope),
      headers: [
        {"event_type", Atom.to_string(envelope.event_type)},
        {"seq", Integer.to_string(envelope.meta.seq)}
      ]
    }
    
    Kaffe.produce_sync("xtrack-events", [message])
  end
end
```

---

## Authentication & Authorization

### API Key Authentication

For TCP transport:

```elixir
defmodule XTrack.Auth do
  def verify_api_key(key) do
    case MyApp.ApiKeys.get(key) do
      nil -> {:error, :invalid_key}
      api_key -> {:ok, api_key.user_id}
    end
  end
end

# In TCP transport, first message must be auth
defmodule XTrack.Transport.AuthenticatedTCP do
  def handle_info({:tcp, socket, data}, %{authenticated: false} = state) do
    case XTrack.Auth.verify_api_key(String.trim(data)) do
      {:ok, user_id} ->
        {:noreply, %{state | authenticated: true, user_id: user_id}}
      {:error, _} ->
        :gen_tcp.close(socket)
        {:stop, :normal, state}
    end
  end
  
  def handle_info({:tcp, socket, data}, %{authenticated: true} = state) do
    # Process events normally
  end
end
```

### Run Permissions

```elixir
defmodule XTrack.Permissions do
  def can_view?(user_id, run_id) do
    run = XTrack.get_run(run_id)
    run.user_id == user_id or run.public?
  end
  
  def can_modify?(user_id, run_id) do
    run = XTrack.get_run(run_id)
    run.user_id == user_id
  end
end

# In LiveView
def mount(%{"run_id" => run_id}, session, socket) do
  user_id = session["user_id"]
  
  if XTrack.Permissions.can_view?(user_id, run_id) do
    # ... normal mount
  else
    {:ok, redirect(socket, to: "/unauthorized")}
  end
end
```
