defmodule SnakeBridge.Application do
  @moduledoc false

  use Application

  alias SnakeBridge.Manifest.Loader

  @impl true
  def start(_type, _args) do
    children = [
      # Cache for schema descriptors
      {SnakeBridge.Cache, []}
      # Session manager (placeholder)
      # {SnakeBridge.Session.Manager, []}
    ]

    opts = [strategy: :one_for_one, name: SnakeBridge.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    strategy =
      Application.get_env(:snakebridge, :compilation_mode) ||
        Application.get_env(:snakebridge, :compilation_strategy, :auto)

    if strategy == :compile_time do
      require Logger
      Logger.info("SnakeBridge: compile_time strategy enabled; skipping runtime manifest load")
    else
      _ = Loader.load_configured()
    end

    {:ok, pid}
  end
end
