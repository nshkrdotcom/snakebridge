defmodule SnakeBridge.Telemetry.RuntimeForwarder do
  @moduledoc """
  Enriches Snakepit runtime telemetry with SnakeBridge context.

  This module listens to Snakepit's call events and re-emits them under
  the `:snakebridge` namespace with additional context like the SnakeBridge
  version and library information.

  ## Events

  Original Snakepit events:
  - `[:snakepit, :call, :start]`
  - `[:snakepit, :call, :stop]`
  - `[:snakepit, :call, :exception]`

  Are forwarded as:
  - `[:snakebridge, :runtime, :call, :start]`
  - `[:snakebridge, :runtime, :call, :stop]`
  - `[:snakebridge, :runtime, :call, :exception]`

  With added metadata:
  - `snakebridge_library` - The library name from the original event
  - `snakebridge_version` - The current SnakeBridge version

  ## Usage

      # In your application startup
      SnakeBridge.Telemetry.RuntimeForwarder.attach()

  """

  @handler_id "snakebridge-runtime-enricher"

  @events [
    [:snakepit, :call, :start],
    [:snakepit, :call, :stop],
    [:snakepit, :call, :exception]
  ]

  @doc """
  Attaches the runtime forwarder to Snakepit events.

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
  Detaches the runtime forwarder.
  """
  @spec detach() :: :ok | {:error, :not_found}
  def detach do
    :telemetry.detach(@handler_id)
  end

  @doc false
  def handle_event([:snakepit, :call, :start], measurements, metadata, _config) do
    enriched = enrich_metadata(metadata)

    :telemetry.execute(
      [:snakebridge, :runtime, :call, :start],
      measurements,
      enriched
    )
  end

  def handle_event([:snakepit, :call, :stop], measurements, metadata, _config) do
    enriched = enrich_metadata(metadata)

    :telemetry.execute(
      [:snakebridge, :runtime, :call, :stop],
      measurements,
      enriched
    )
  end

  def handle_event([:snakepit, :call, :exception], measurements, metadata, _config) do
    enriched = enrich_metadata(metadata)

    :telemetry.execute(
      [:snakebridge, :runtime, :call, :exception],
      measurements,
      enriched
    )
  end

  defp enrich_metadata(metadata) do
    library = Map.get(metadata, :library)

    Map.merge(metadata, %{
      snakebridge_library: library,
      snakebridge_version: version()
    })
  end

  defp version do
    Application.spec(:snakebridge, :vsn) |> to_string()
  end
end
