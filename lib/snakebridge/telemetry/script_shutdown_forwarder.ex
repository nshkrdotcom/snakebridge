defmodule SnakeBridge.Telemetry.ScriptShutdownForwarder do
  @moduledoc """
  Forwards Snakepit script shutdown telemetry events under the SnakeBridge namespace.

  This module re-emits:
  - `[:snakepit, :script, :shutdown, :start|:stop|:cleanup|:exit]`
  as
  - `[:snakebridge, :script, :shutdown, :start|:stop|:cleanup|:exit]`
  with `snakebridge_version` metadata.
  """

  @handler_id "snakebridge-script-shutdown-forwarder"

  @events [
    [:snakepit, :script, :shutdown, :start],
    [:snakepit, :script, :shutdown, :stop],
    [:snakepit, :script, :shutdown, :cleanup],
    [:snakepit, :script, :shutdown, :exit]
  ]

  @doc """
  Attaches the shutdown forwarder to Snakepit script shutdown events.

  Returns `:ok` on success or `{:error, :already_exists}` if already attached.
  """
  @spec attach() :: :ok | {:error, :already_exists}
  def attach do
    :telemetry.attach_many(
      @handler_id,
      @events,
      &handle_event/4,
      %{}
    )
  end

  @doc """
  Detaches the shutdown forwarder.
  """
  @spec detach() :: :ok | {:error, :not_found}
  def detach do
    :telemetry.detach(@handler_id)
  end

  @doc false
  def handle_event([:snakepit, :script, :shutdown, phase], measurements, metadata, _config) do
    :telemetry.execute(
      [:snakebridge, :script, :shutdown, phase],
      measurements,
      Map.put(metadata, :snakebridge_version, version())
    )
  end

  defp version do
    Application.spec(:snakebridge, :vsn) |> to_string()
  end
end
