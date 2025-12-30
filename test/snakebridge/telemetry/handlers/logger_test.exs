defmodule SnakeBridge.Telemetry.Handlers.LoggerTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.Telemetry.Handlers.Logger, as: LoggerHandler

  setup do
    # Detach any existing handlers
    :telemetry.detach("snakebridge-logger")

    on_exit(fn ->
      :telemetry.detach("snakebridge-logger")
    end)

    :ok
  end

  describe "attach/0" do
    test "attaches to expected events without error" do
      assert :ok = LoggerHandler.attach()
    end

    test "can be detached" do
      :ok = LoggerHandler.attach()
      assert :ok = LoggerHandler.detach()
    end
  end

  describe "handle_event/4" do
    test "handles compile stop event" do
      # Test that the handler doesn't crash when handling events
      LoggerHandler.attach()

      # This should not raise
      :telemetry.execute(
        [:snakebridge, :compile, :stop],
        %{
          duration: System.convert_time_unit(1500, :millisecond, :native),
          symbols_generated: 100,
          files_written: 10
        },
        %{library: :all, phase: :compile, details: %{libraries: [:numpy, :torch], mode: :normal}}
      )
    end

    test "handles compile exception event" do
      LoggerHandler.attach()

      # This should not raise
      :telemetry.execute(
        [:snakebridge, :compile, :exception],
        %{duration: System.convert_time_unit(500, :millisecond, :native)},
        %{
          library: :all,
          phase: :compile,
          details: %{reason: %RuntimeError{message: "test error"}, stacktrace: []}
        }
      )
    end

    test "handles introspect stop event" do
      LoggerHandler.attach()

      # This should not raise
      :telemetry.execute(
        [:snakebridge, :compile, :introspect, :stop],
        %{
          duration: System.convert_time_unit(250, :millisecond, :native),
          symbols_introspected: 25,
          cache_hits: 5
        },
        %{
          library: :numpy,
          phase: :introspect,
          details: %{python_time: System.convert_time_unit(200, :millisecond, :native)}
        }
      )
    end

    test "handles generate stop event" do
      LoggerHandler.attach()

      # This should not raise
      :telemetry.execute(
        [:snakebridge, :compile, :generate, :stop],
        %{
          duration: System.convert_time_unit(100, :millisecond, :native),
          bytes_written: 5000,
          functions_generated: 20,
          classes_generated: 3
        },
        %{library: :numpy, phase: :generate, details: %{file: "lib/numpy.ex"}}
      )
    end
  end
end
