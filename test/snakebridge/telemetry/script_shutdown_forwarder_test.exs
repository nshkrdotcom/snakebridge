defmodule SnakeBridge.Telemetry.ScriptShutdownForwarderTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.Telemetry.ScriptShutdownForwarder

  setup do
    :telemetry.detach("snakebridge-script-shutdown-forwarder")

    on_exit(fn ->
      :telemetry.detach("snakebridge-script-shutdown-forwarder")
    end)

    :ok
  end

  describe "attach/0" do
    test "attaches to snakepit script shutdown events" do
      assert :ok = ScriptShutdownForwarder.attach()
    end
  end

  describe "event forwarding" do
    setup do
      case ScriptShutdownForwarder.attach() do
        :ok ->
          :ok

        {:error, :already_exists} ->
          :telemetry.detach("snakebridge-script-shutdown-forwarder")
          :ok = ScriptShutdownForwarder.attach()
      end

      :ok
    end

    test "forwards shutdown start events with version metadata" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-script-forwarder",
        [:snakebridge, :script, :shutdown, :start],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("test-script-forwarder") end)

      :telemetry.execute(
        [:snakepit, :script, :shutdown, :start],
        %{system_time: System.system_time()},
        %{run_id: "run-123", exit_mode: :none}
      )

      assert_receive {:telemetry_event, ^ref, [:snakebridge, :script, :shutdown, :start],
                      _measurements, metadata}

      assert metadata.run_id == "run-123"
      assert is_binary(metadata.snakebridge_version)
    end

    test "forwards shutdown cleanup events" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-script-forwarder-cleanup",
        [:snakebridge, :script, :shutdown, :cleanup],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("test-script-forwarder-cleanup") end)

      :telemetry.execute(
        [:snakepit, :script, :shutdown, :cleanup],
        %{duration: 1000},
        %{run_id: "run-456", cleanup_result: :ok}
      )

      assert_receive {:telemetry_event, ^ref, [:snakebridge, :script, :shutdown, :cleanup],
                      measurements, metadata}

      assert measurements.duration == 1000
      assert metadata.cleanup_result == :ok
    end
  end
end
