defmodule SnakeBridge.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Suppress noisy logs from OpenTelemetry transitive dependencies
    # These apps emit info/notice logs during startup that pollute console output
    # Users can override by setting their own log levels in config
    suppress_otel_transitive_logs()

    children = [
      SnakeBridge.SessionManager,
      SnakeBridge.CallbackRegistry
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: SnakeBridge.Supervisor)
  end

  defp suppress_otel_transitive_logs do
    # ssl/public_key can log "Loading X CA(s) from ..." at info/notice level
    Logger.put_application_level(:ssl, :warning)
    Logger.put_application_level(:public_key, :warning)
    # opentelemetry_exporter can log during exporter init
    Logger.put_application_level(:opentelemetry_exporter, :warning)
  end
end
