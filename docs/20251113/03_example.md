> Update (2025-12-23): This example targets Snakepit 0.6.x and a legacy config-centric workflow. Current SnakeBridge targets Snakepit 0.7.0 with manifest-driven generation. Use this as historical reference.

Nice, let’s make this concrete. Here’s a **“works-today” cluster demo** that uses:

* **Plain OTP distribution** (`--sname`, `Node.connect/1`, `:rpc.call/4`)
* **Current Snakepit 0.6.10** (no new cluster APIs yet)
* **SnakeBridge** on top, calling into Python via Snakepit

The idea: two BEAM nodes both run Snakepit + SnakeBridge. From node A you:

1. Call SnakeBridge **locally** (Python on A).
2. Call SnakeBridge **remotely** via `:rpc` (Python on B).
3. See that both are using the same Snakepit-powered Python runtime, just on different nodes.

You can drop this into the SnakeBridge repo as `examples/cluster_demo.exs` + a doc snippet.

---

## 1. App config (Elixir project that uses SnakeBridge + Snakepit)

In your **user app** (not `snakebridge` itself), you’d have something like:

```elixir
# mix.exs
def deps do
  [
    {:snakepit, "~> 0.6.10"},
    {:snakebridge, "~> 0.2.4"}
  ]
end
```

Then configure Snakepit to use the SnakeBridge adapter as its Python adapter:

```elixir
# config/config.exs (or config/dev.exs)

import Config

config :snakepit,
  # single pool for demo; both nodes will use same config
  pools: [
    %{
      name: :snakebridge,
      worker_profile: :process,
      pool_size: 4,
      # Snakepit’s GRPCPython adapter (or whatever you already use)
      adapter_module: Snakepit.Adapters.GRPCPython,
      # Adapter args so the Python side loads SnakeBridgeAdapter
      # (this matches however your Snakepit CLI expects adapter args)
      adapter_args: [
        "--adapter-module", "snakebridge_adapter.adapter",
        "--adapter-class",  "SnakeBridgeAdapter"
      ]
    }
  ]

# Example: disable heartbeats for local dev if you want
config :snakepit,
  heartbeat: %{
    enabled: true,
    ping_interval_ms: 2_000,
    timeout_ms: 10_000,
    max_missed_heartbeats: 3,
    dependent: true
  }
```

> If your current Snakepit config looks slightly different, keep using that — the cluster demo only cares that both nodes have *the same* Snakepit config and are able to start Python workers with the SnakeBridge adapter.

---

## 2. Cluster demo script (in SnakeBridge repo)

Add this file inside **SnakeBridge** itself:

```elixir
# examples/cluster_demo.exs
#
# Usage:
#
# 1) Start first node:
#    elixir --sname snake_a -S mix run examples/cluster_demo.exs --no-start
#
# 2) In another terminal, start second node:
#    elixir --sname snake_b -S mix run examples/cluster_demo.exs --no-start
#
# 3) On node :snake_a, in IEx:
#    iex(snake_a@host)> SnakeBridge.ClusterDemo.run(:"snake_b@host")
#

Mix.ensure_application!(:logger)
Mix.ensure_application!(:snakepit)
Mix.ensure_application!(:snakebridge)

defmodule SnakeBridge.ClusterDemo do
  @moduledoc """
  Minimal distributed demo:

  - Both nodes run Snakepit + SnakeBridge.
  - We call JSON functions locally and on a remote node.
  """

  require Logger
  alias SnakeBridge.Discovery
  alias SnakeBridge.Runtime

  @doc """
  Run the cluster demo by targeting a remote node.

  Example:

      SnakeBridge.ClusterDemo.run(:"snake_b@host")

  """
  def run(remote_node) when is_atom(remote_node) do
    Logger.info("Local node: #{inspect(node())}")
    Logger.info("Target remote node: #{inspect(remote_node)}")

    case Node.connect(remote_node) do
      true ->
        Logger.info("✓ Connected to #{inspect(remote_node)} (nodes: #{inspect(Node.list())})")
        run_local_demo()
        run_remote_demo(remote_node)

      false ->
        Logger.error("Could not connect to #{inspect(remote_node)}")
        :error
    end
  end

  # --- LOCAL DEMO ----------------------------------------------------------

  defp run_local_demo do
    Logger.info("== Local demo: calling Python json module via SnakeBridge on #{inspect(node())}")

    with {:ok, schema} <- Discovery.discover("json"),
         config <- Discovery.schema_to_config(schema, python_module: "json"),
         {:ok, modules} <- SnakeBridge.generate(config),
         json_mod <- find_json_module(modules),
         {:ok, encoded} <- json_mod.dumps(%{obj: %{hello: "local", node: Atom.to_string(node())}}),
         {:ok, decoded} <- json_mod.loads(%{s: encoded}) do
      Logger.info("Local json.dumps => #{encoded}")
      Logger.info("Local json.loads => #{inspect(decoded)}")
    else
      other ->
        Logger.error("Local demo failed: #{inspect(other)}")
    end
  end

  # --- REMOTE DEMO ---------------------------------------------------------

  defp run_remote_demo(remote_node) do
    Logger.info(
      "== Remote demo: asking #{inspect(remote_node)} to run the same SnakeBridge flow"
    )

    fun = fn ->
      require Logger
      alias SnakeBridge.Discovery

      Logger.info("Remote side running on #{inspect(node())}")

      with {:ok, schema} <- Discovery.discover("json"),
           config <- Discovery.schema_to_config(schema, python_module: "json"),
           {:ok, modules} <- SnakeBridge.generate(config),
           json_mod <- find_json_module(modules),
           {:ok, encoded} <-
             json_mod.dumps(%{obj: %{hello: "remote", node: Atom.to_string(node())}}),
           {:ok, decoded} <- json_mod.loads(%{s: encoded}) do
        {encoded, decoded}
      else
        other -> {:error, other}
      end
    end

    case :rpc.call(remote_node, __MODULE__, :run_remote_fun, [fun]) do
      {encoded, decoded} ->
        Logger.info("Remote json.dumps => #{encoded}")
        Logger.info("Remote json.loads => #{inspect(decoded)}")

      {:error, reason} ->
        Logger.error("Remote demo failed: #{inspect(reason)}")

      other ->
        Logger.error("Unexpected remote result: #{inspect(other)}")
    end
  end

  # tiny helper so we can :rpc.call/4 with a named function
  def run_remote_fun(fun) when is_function(fun, 0), do: fun.()

  # --- Helpers -------------------------------------------------------------

  defp find_json_module(modules) do
    Enum.find(modules, fn mod ->
      function_exported?(mod, :dumps, 2) and function_exported?(mod, :loads, 2)
    end) ||
      raise "Could not find generated json module with dumps/2 & loads/2"
  end
end
```

This doesn’t rely on any new Snakepit “cluster API”; it just uses:

* OTP distribution (`Node.connect/1`, `:rpc.call/4`)
* SnakeBridge discovery/generation (`SnakeBridge.discover/2`, `SnakeBridge.generate/1`)
* SnakeBridge → Snakepit → Python pipeline that you already have.

---

## 3. How to run the demo

From the **SnakeBridge repo** (or from your app that depends on SnakeBridge + Snakepit):

1. Make sure Python/venv is set up so Snakepit can launch Python workers with the SnakeBridge adapter.

2. Start node A:

```bash
# terminal 1
SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3 \
elixir --sname snake_a -S mix run --no-start
```

Then in IEx:

```elixir
iex(snake_a@your-host)> Mix.ensure_application!(:snakebridge)
iex(snake_a@your-host)> Mix.ensure_application!(:snakepit)
iex(snake_a@your-host)> Code.require_file("examples/cluster_demo.exs")
```

3. Start node B:

```bash
# terminal 2
SNAKEPIT_PYTHON=$(pwd)/.venv/bin/python3 \
elixir --sname snake_b -S mix run --no-start
```

In IEx:

```elixir
iex(snake_b@your-host)> Mix.ensure_application!(:snakebridge)
iex(snake_b@your-host)> Mix.ensure_application!(:snakepit)
iex(snake_b@your-host)> Code.require_file("examples/cluster_demo.exs")
```

4. Back on node A, run the demo:

```elixir
iex(snake_a@your-host)> SnakeBridge.ClusterDemo.run(:"snake_b@your-host")
```

You should see logs like:

* Local node calling `json.dumps/loads` via SnakeBridge → Snakepit → Python on `snake_a`.
* Remote node doing the same on `snake_b` via `:rpc`.

That’s your **minimum viable cluster story**: “any node that runs Snakepit can execute Python; any other node can delegate work to it via `:rpc`”.

---

## 4. How this evolves into “Snakepit 2.0 cluster mode”

Right now this example uses **manual** `Node.connect/1` + `:rpc.call/4`. The future steps we talked about are basically:

* Wrap that in a `Snakepit.Cluster` module & config (`node_selector`, etc.).
* Make `Snakepit.Pool.execute/…` cluster-aware so you don’t have to call `:rpc` yourself.
* Add job/workflow layer on top.

But this demo already:

* Works with **current** Snakepit 0.6.10 + SnakeBridge.
* Shows **SnakeBridge modules working across nodes**.
* Is a nice starting point for docs (e.g. `examples/CLUSTER_DEMO.md`).

If you want, next step I can sketch is a **“pseudo-API”** for `Snakepit.Cluster` / `node_selector` that this demo would eventually collapse into, so you have a concrete target for library changes.
