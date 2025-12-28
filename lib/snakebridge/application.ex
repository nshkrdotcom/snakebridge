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

    children = []
    Supervisor.start_link(children, strategy: :one_for_one, name: SnakeBridge.Supervisor)
  end

  defp suppress_otel_transitive_logs do
    # tls_certificate_check logs "Loading X CA(s) from ..." at notice level
    Logger.put_application_level(:tls_certificate_check, :warning)
    # opentelemetry_exporter can log during exporter init
    Logger.put_application_level(:opentelemetry_exporter, :warning)
  end
end
