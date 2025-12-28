defmodule SnakeBridge.Telemetry.Handlers.MetricsTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Telemetry.Handlers.Metrics

  describe "metrics/0" do
    test "returns a list of metric definitions" do
      metrics = Metrics.metrics()

      assert is_list(metrics)
      assert length(metrics) > 0
    end

    test "includes compile metrics" do
      metrics = Metrics.metrics()

      metric_names = Enum.map(metrics, & &1.name)

      assert [:snakebridge, :compile, :duration] in metric_names
      assert [:snakebridge, :compile, :symbols_generated] in metric_names
      assert [:snakebridge, :compile, :total] in metric_names
    end

    test "includes scan metrics" do
      metrics = Metrics.metrics()

      metric_names = Enum.map(metrics, & &1.name)

      assert [:snakebridge, :scan, :duration] in metric_names
      assert [:snakebridge, :scan, :files_scanned] in metric_names
    end

    test "includes introspect metrics" do
      metrics = Metrics.metrics()

      metric_names = Enum.map(metrics, & &1.name)

      assert [:snakebridge, :introspect, :duration] in metric_names
      assert [:snakebridge, :introspect, :symbols_introspected] in metric_names
    end

    test "includes generate metrics" do
      metrics = Metrics.metrics()

      metric_names = Enum.map(metrics, & &1.name)

      assert [:snakebridge, :generate, :duration] in metric_names
      assert [:snakebridge, :generate, :bytes_written] in metric_names
    end

    test "includes docs metrics" do
      metrics = Metrics.metrics()

      metric_names = Enum.map(metrics, & &1.name)

      assert [:snakebridge, :docs, :fetch, :duration] in metric_names
    end
  end
end
