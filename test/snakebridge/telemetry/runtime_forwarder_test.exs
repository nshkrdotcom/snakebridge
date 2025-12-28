defmodule SnakeBridge.Telemetry.RuntimeForwarderTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.Telemetry.RuntimeForwarder

  setup do
    # Detach any existing handlers
    :telemetry.detach("snakebridge-runtime-enricher")

    on_exit(fn ->
      :telemetry.detach("snakebridge-runtime-enricher")
    end)

    :ok
  end

  describe "attach/0" do
    test "attaches to snakepit call events" do
      assert :ok = RuntimeForwarder.attach()
    end
  end

  describe "event forwarding" do
    setup do
      RuntimeForwarder.attach()
      :ok
    end

    test "forwards call start events with enriched metadata" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-forwarder",
        [:snakebridge, :runtime, :call, :start],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("test-forwarder") end)

      # Simulate Snakepit emitting a call start event
      :telemetry.execute(
        [:snakepit, :call, :start],
        %{system_time: System.system_time()},
        %{library: "numpy", function: "array"}
      )

      assert_receive {:telemetry_event, ^ref, [:snakebridge, :runtime, :call, :start],
                      _measurements, metadata}

      assert metadata.snakebridge_library == "numpy"
      assert is_binary(metadata.snakebridge_version)
    end

    test "forwards call stop events with enriched metadata" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-forwarder",
        [:snakebridge, :runtime, :call, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("test-forwarder") end)

      :telemetry.execute(
        [:snakepit, :call, :stop],
        %{duration: 1000, queue_time: 100},
        %{library: "torch", function: "tensor", result: :ok}
      )

      assert_receive {:telemetry_event, ^ref, [:snakebridge, :runtime, :call, :stop],
                      measurements, metadata}

      assert measurements.duration == 1000
      assert metadata.snakebridge_library == "torch"
    end

    test "forwards call exception events with enriched metadata" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-forwarder",
        [:snakebridge, :runtime, :call, :exception],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("test-forwarder") end)

      :telemetry.execute(
        [:snakepit, :call, :exception],
        %{duration: 500},
        %{library: "numpy", function: "array", kind: :error, reason: %RuntimeError{}}
      )

      assert_receive {:telemetry_event, ^ref, [:snakebridge, :runtime, :call, :exception],
                      _measurements, metadata}

      assert metadata.snakebridge_library == "numpy"
      assert metadata.kind == :error
    end
  end
end
