defmodule SnakeBridge.TelemetryConsistencyTest do
  use ExUnit.Case, async: true

  describe "telemetry event schema" do
    test "compile events have consistent metadata" do
      events = [
        [:snakebridge, :compile, :scan, :stop],
        [:snakebridge, :compile, :introspect, :stop],
        [:snakebridge, :compile, :generate, :stop]
      ]

      for event <- events do
        metadata = SnakeBridge.Telemetry.event_metadata_schema(event)
        assert :library in metadata
        assert :phase in metadata
      end
    end

    test "runtime events have consistent metadata" do
      events = [
        [:snakebridge, :runtime, :call, :start],
        [:snakebridge, :runtime, :call, :stop]
      ]

      for event <- events do
        metadata = SnakeBridge.Telemetry.event_metadata_schema(event)
        assert :library in metadata
        assert :function in metadata
      end
    end
  end
end
