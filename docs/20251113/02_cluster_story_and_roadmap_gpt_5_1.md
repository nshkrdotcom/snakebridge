> Update (2025-12-23): This roadmap references Snakepit 0.6.x and a legacy config-centric workflow. Current SnakeBridge is manifest-driven on Snakepit 0.7.0. Use this as historical context.

Nice. Let’s keep the “future history” of Snakepit/SnakeBridge rolling then 😄

Below is something you can pretty much drop into a `docs/ROADMAP_SNAKEPIT_2_0.md` / `docs/CLUSTER_STORY.md` and iterate on.

---

## Snakepit 2.0 – Cluster Story & Roadmap

This is a sketch of how Snakepit evolves from “single-node process/thread pooler” into “cluster-aware AI control plane for Python (and friends)”, and how SnakeBridge rides on top of that.

Think in **layers**:

1. **Local Engine** – what already exists in 0.6.x.
2. **Cluster Engine** – spread pools across nodes.
3. **Job/Workflow Layer** – durable work model.
4. **Platform Layer** – multi-tenant, observability, UX.
5. **Managed / “Anyscale-adjacent”** – optional long-term.

---

## 0. Baseline: What Snakepit 0.6.x Already Is

You already have a strong single-node story:

* **Core:**

  * `Snakepit.Pool` – multi-pool manager, queue, backpressure, TTL & request-count recycling, session affinity.
  * `Snakepit.Pool.WorkerSupervisor` + `Worker.Starter` – per-worker supervision, restarts.
  * `Snakepit.Pool.ProcessRegistry` – DETS backed, BEAM run_id + OS PID tracking, orphan cleanup.
  * `Snakepit.ProcessKiller` – robust SIGTERM/SIGKILL + `/proc` / `ps`-based introspection.
  * `Snakepit.GRPCWorker` – gRPC worker with heartbeat, OpenTelemetry spans, telemetry stream.

* **Python side:**

  * `grpc_server.py` / `grpc_server_threaded.py` – process vs free-threaded servers.
  * `snakepit_bridge.*` – adapters, telemetry, session context, serialization.

You can basically say: *“One BEAM node, N pools, M Python workers, full lifecycle hygiene.”*

Snakepit 2.0 is: **how do we keep that exact semantics but spread it across a cluster of BEAM nodes**.

---

## 1. Cluster Engine: Multi-node Pools

### 1.1. Cluster Topology

**Goal:** a cluster of Elixir nodes where **any node can run Python workers**, but pool semantics remain “one logical pool”.

Basic design:

* **Control nodes:**
  all nodes running `Snakepit.Application` (and thus `Snakepit.Pool`, `ProcessRegistry`, etc.).

* **Worker placement:**

  * Each pool config gets a `node_selector` field:

    ```elixir
    %{
      name: :hpc,
      worker_profile: :thread,
      pool_size: 32,
      node_selector: {:any, role: :worker} # or {:only, [:"node@host1", :"node@host2"]}
    }
    ```
  * At init, pool splits `pool_size` across chosen nodes.
  * Per-node `Snakepit.Pool` child (or a single distributed `Pool` that delegates per-node instantiation).

### 1.2. Global Registry

Today:

* `Snakepit.Pool.Registry` is local per node.

Cluster version options:

* **Option A – Keep local registry + global index:**

  * Local `Pool.Registry` stays as-is.
  * Add `Snakepit.Cluster.Registry`:

    * ETS or Mnesia table keyed by `{node(), worker_id}`.
    * Only used for:

      * routing (“which node has worker_id?”),
      * cross-node `execute` calls.

* **Option B – Horde / :syn / :pg:**

  * Use Horde Registry or `syn` to replicate worker metadata.
  * `fetch_worker/worker_id` becomes location-transparent.

Realistically, **Option A** is less magic and keeps your current API stable; you layer the cluster index on top.

### 1.3. Cross-node Execute

Currently:

```elixir
Snakepit.execute("command", args, pool: Snakepit.Pool)
```

In cluster mode:

* **API stays** the same.
* Implementation:

  * `Snakepit.Pool.execute/3`:

    1. Select a pool **instance** on a node (local or remote).
    2. If remote, use `:rpc.call(node, Snakepit.Pool, :execute, [...])`.
    3. Use existing queue/backpressure semantics on that remote node.

This is where OTP shines: you don’t invent your own protocol – you use `:rpc`/`node()` and treat remote pools like local.

### 1.4. Placement & Balancing

Phase 1 – static:

* Use pool config to decide:

  * which nodes host workers,
  * how many workers per node.

Phase 2 – adaptive:

* Add a small scheduler:

  * track per-node stats via Telemetry (workers, queue depth, CPU/mem),
  * choose node with least load when scheduling new workers or placing a job.

---

## 2. Job / Workflow Layer

Once pools can span nodes, you can add a “job” abstraction on top of streaming and execute.

### 2.1. Jobs as OTP Processes

Add a `Snakepit.Job` GenServer (or use `DynamicSupervisor`):

* **Responsibilities:**

  * Accepts a request: `{session_id, tool_name, args, opts}`.
  * Picks pool / node, calls `Snakepit.execute_in_session`.
  * Tracks retries, status, metrics.

* **State example:**

  ```elixir
  %Snakepit.Job{
    id: "job-123",
    session_id: "sess-1",
    tool: "generate_text_stream",
    status: :running | :succeeded | :failed | :cancelled,
    attempts: 1,
    last_error: nil
  }
  ```

This is the Ray “task”/“actor” mental model, but implemented as Elixir processes.

### 2.2. Persistent Jobs (Optional Later)

If you want real infra:

* Store job metadata in Postgres (via Ecto).
* `Snakepit.JobSupervisor`:

  * On startup, reads “pending/running” jobs from DB and re-drives them (like Oban, Broadway, etc.).
* This gives you:

  * Durable queue,
  * Crash/restart semantics at job level on top of Snakepit pools.

---

## 3. SnakeBridge on Top of the Cluster

SnakeBridge already uses a `Snakebridge.SnakepitAdapter` that calls:

```elixir
Snakepit.execute_in_session(session_id, tool_name, args, opts)
```

Once Snakepit is cluster-aware, SnakeBridge **automatically** benefits:

* **Codegen modules** (e.g. `Demo.Predict`) stay the same.
* Runtime (`SnakeBridge.Runtime`) doesn’t care where the workers live.
* You can add cluster-aware options to config:

  ```elixir
  %SnakeBridge.Config{
    python_module: "demo",
    grpc: %{
      enabled: true,
      pool_name: :demo_pool,
      node_selector: {:any, role: :worker}
    }
  }
  ```

This keeps the layering very clean:

* SnakeBridge = “how do we **describe and generate** code for Python libs”.
* Snakepit = “how do we **run** those tools across processes/nodes”.

---

## 4. Python-side Story as You Scale

### 4.1. Adapter Contracts

Right now:

* `Snakepit.Handler` expects Python to implement:

  * `execute_tool`,
  * optional streaming methods.

For Snakepit 2.0, some expectations get more important:

* Adapters *must* be:

  * **thread-safe** if run under `grpc_server_threaded.py` (`__thread_safe__ = True`).
  * explicit about external state (e.g., shared GPU/CPU resources).

You’re already enforcing:

* `grpc_server_threaded.py` refuses adapters that don’t declare `__thread_safe__`.

Cluster story doesn’t require Python changes immediately, but you want:

* Good docs for adapter authors,
* Template adapters (`TemplateAdapter`, `SnakeBridgeAdapter`, `GenAIAdapter`, etc.) that follow the patterns.

### 4.2. Per-node capabilities

Longer term, for cluster scheduling, you can expose from each Python worker:

* “caps” like:

  * `python_version`,
  * `libraries` (with versions),
  * `gpu: true/false`, etc.

Then SnakeBridge configs could request a specific capability set (“run this library only on nodes with GPU + correct version”).

---

## 5. Draft Roadmap (Milestones)

### Milestone A – Snakepit 0.7.x: Cluster-Ready Internals (but still single node)

* Clean boundary for:

  * `Pool` vs `Pool.Registry` vs `ProcessRegistry`.
* Telemetry naming stabilized (`Snakepit.Telemetry.Naming`, Python catalog).
* Threaded gRPC worker path solid (which you’re already doing).
* Python test harness stable (`test_python.sh` & `.venv` story – you’re close).

This is basically where you are now with 0.6.10.

---

### Milestone B – Snakepit 0.8.x: Multi-node Pools (MVP)

* Add `node_selector` to pool config.
* Introduce a simple `Snakepit.Cluster` module:

  * manages a list of nodes,
  * simple CLI / Mix tasks to join/leave nodes for dev (“mini cluster”).
* Allow a `pool` to be instantiated on multiple nodes:

  * `pool_size` per node, or split evenly.
* Keep scheduling naive (round-robin) but working.

Deliverables:

* Docs `docs/CLUSTER_OVERVIEW.md`.
* Example: `examples/cluster_demo.exs` – spawns two BEAM nodes, each with Python workers, then loads across both.

---

### Milestone C – SnakeBridge 0.3.x: Cluster-aware Configs

* Extend `SnakeBridge.Config.grpc` with:

  * `pool_name`,
  * `node_selector`.
* Simple GUI/CLI to:

  * list current pools,
  * show which nodes they run on,
  * show which Python libraries/adapters are available.

---

### Milestone D – Snakepit 0.9.x: Job / Workflow Layer

* `Snakepit.Job` GenServer + `JobSupervisor`.

* Basic job API:

  ```elixir
  {:ok, job_id} = Snakepit.Job.enqueue(:demo_pool, "some_tool", args, opts)
  {:ok, status} = Snakepit.Job.status(job_id)
  ```

* Optional Postgres-backed persistence.

---

### Milestone E – 1.x: Platform / Tenancy / Polishing

* Multi-tenant config:

  * per-tenant pools (or quotas),
  * simple auth story for external callers.
* Tight integration with:

  * Prometheus / Grafana (metrics),
  * OTEL tracing (already partly done).
* Turn docs into more official “Snakepit Platform” & “SnakeBridge Integration Guide”.

---

## 6. Positioning (Reality Check)

This plan doesn’t require you to “beat Ray at its own game”. Instead:

* **Snakepit** = BEAM-native control plane for Python workers (and later, other runtimes).
* **SnakeBridge** = schema → config → Elixir modules for Python libs, powered by Snakepit.
* You become **the way** to do serious Python/ML orchestration from Elixir.

And if one day there’s a Ray adapter that SnakeBridge can introspect/call into? Even better: you bridge **through** Ray clusters instead of fighting them.

---

If you’d like, next document I can sketch is a **full example**:

* `config :snakepit, pools: [...]` for a 2-node cluster,
* a small `mix` task to boot a local cluster (`mix snakepit.demo_cluster`),
* and a SnakeBridge config + generated module that calls out to a Python library across that cluster.

That’s basically a mini “hello, distributed Snakepit+SnakeBridge” story you can ship as a tutorial.
