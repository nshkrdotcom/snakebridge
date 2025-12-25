defmodule SnakeBridge.Application do
  @moduledoc """
  SnakeBridge application supervisor.

  This module provides the OTP application callback for SnakeBridge.
  Currently implements a minimal supervision tree.

  ## Configuration

  SnakeBridge can be configured via Mix config:

      config :snakebridge,
        auto_start_snakepit: true,
        python_executable: "python3",
        python_path: []

  ## Supervision

  The application starts an empty supervisor that can be extended
  in the future to manage:

  - Connection pools
  - Telemetry handlers
  - Registry processes
  - Cache managers

  Currently, SnakeBridge relies on Snakepit for Python process management,
  so this supervisor remains minimal.
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    Logger.debug("Starting SnakeBridge application")

    children = [
      # Registry for tracking generated adapters
      {SnakeBridge.Registry, []}
      # Future: Add more supervised processes
      # {SnakeBridge.Telemetry, []},
    ]

    opts = [strategy: :one_for_one, name: SnakeBridge.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def stop(_state) do
    Logger.debug("Stopping SnakeBridge application")
    :ok
  end
end
