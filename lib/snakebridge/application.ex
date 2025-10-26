defmodule SnakeBridge.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Cache for schema descriptors
      {SnakeBridge.Cache, []}
      # Session manager (placeholder)
      # {SnakeBridge.Session.Manager, []}
    ]

    opts = [strategy: :one_for_one, name: SnakeBridge.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
