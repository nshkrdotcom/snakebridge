defmodule SnakeBridge.TelemetryTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Telemetry

  setup do
    # Detach any existing handlers that might interfere
    :telemetry.detach("test-telemetry-handler")

    on_exit(fn ->
      :telemetry.detach("test-telemetry-handler")
    end)

    :ok
  end

  describe "compile_start/2" do
    test "emits compile start event" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-telemetry-handler",
        [:snakebridge, :compile, :start],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
        end,
        nil
      )

      Telemetry.compile_start([:numpy, :torch], false)

      assert_receive {:telemetry_event, ^ref, [:snakebridge, :compile, :start], measurements,
                      metadata}

      assert is_integer(measurements.system_time)
      assert metadata.library == :all
      assert metadata.phase == :compile
      assert metadata.details.libraries == [:numpy, :torch]
      assert metadata.details.strict == false
    end
  end

  describe "compile_stop/5" do
    test "emits compile stop event with measurements" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-telemetry-handler",
        [:snakebridge, :compile, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
        end,
        nil
      )

      start_time = System.monotonic_time()
      Telemetry.compile_stop(start_time, 42, 5, [:numpy], :normal)

      assert_receive {:telemetry_event, ^ref, [:snakebridge, :compile, :stop], measurements,
                      metadata}

      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
      assert measurements.symbols_generated == 42
      assert measurements.files_written == 5
      assert metadata.library == :all
      assert metadata.phase == :compile
      assert metadata.details.libraries == [:numpy]
      assert metadata.details.mode == :normal
    end
  end

  describe "scan_stop/4" do
    test "emits scan stop event" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-telemetry-handler",
        [:snakebridge, :compile, :scan, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
        end,
        nil
      )

      start_time = System.monotonic_time()
      Telemetry.scan_stop(start_time, 10, 25, ["lib", "test"])

      assert_receive {:telemetry_event, ^ref, [:snakebridge, :compile, :scan, :stop],
                      measurements, metadata}

      assert is_integer(measurements.duration)
      assert measurements.files_scanned == 10
      assert measurements.symbols_found == 25
      assert metadata.library == :all
      assert metadata.phase == :scan
      assert metadata.details.paths == ["lib", "test"]
    end
  end

  describe "introspect_start/2" do
    test "emits introspect start event" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-telemetry-handler",
        [:snakebridge, :compile, :introspect, :start],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
        end,
        nil
      )

      Telemetry.introspect_start(:numpy, 15)

      assert_receive {:telemetry_event, ^ref, [:snakebridge, :compile, :introspect, :start],
                      measurements, metadata}

      assert is_integer(measurements.system_time)
      assert metadata.library == :numpy
      assert metadata.phase == :introspect
      assert metadata.details.batch_size == 15
    end
  end

  describe "introspect_stop/5" do
    test "emits introspect stop event" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-telemetry-handler",
        [:snakebridge, :compile, :introspect, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
        end,
        nil
      )

      start_time = System.monotonic_time()
      Telemetry.introspect_stop(start_time, :numpy, 15, 5, 100_000)

      assert_receive {:telemetry_event, ^ref, [:snakebridge, :compile, :introspect, :stop],
                      measurements, metadata}

      assert is_integer(measurements.duration)
      assert measurements.symbols_introspected == 15
      assert measurements.cache_hits == 5
      assert metadata.library == :numpy
      assert metadata.phase == :introspect
      assert metadata.details.python_time == 100_000
    end
  end

  describe "generate_stop/6" do
    test "emits generate stop event" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-telemetry-handler",
        [:snakebridge, :compile, :generate, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
        end,
        nil
      )

      start_time = System.monotonic_time()
      Telemetry.generate_stop(start_time, :numpy, "lib/numpy.ex", 5000, 20, 5)

      assert_receive {:telemetry_event, ^ref, [:snakebridge, :compile, :generate, :stop],
                      measurements, metadata}

      assert is_integer(measurements.duration)
      assert measurements.bytes_written == 5000
      assert measurements.functions_generated == 20
      assert measurements.classes_generated == 5
      assert metadata.library == :numpy
      assert metadata.phase == :generate
      assert metadata.details.file == "lib/numpy.ex"
    end
  end

  describe "docs_fetch/4" do
    test "emits docs fetch event" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-telemetry-handler",
        [:snakebridge, :docs, :fetch],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
        end,
        nil
      )

      start_time = System.monotonic_time()
      Telemetry.docs_fetch(start_time, Numpy, :array, :cache)

      assert_receive {:telemetry_event, ^ref, [:snakebridge, :docs, :fetch], measurements,
                      metadata}

      assert is_integer(measurements.duration)
      assert metadata.module == Numpy
      assert metadata.function == :array
      assert metadata.source == :cache
    end
  end

  describe "lock_verify/3" do
    test "emits lock verify event" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-telemetry-handler",
        [:snakebridge, :lock, :verify],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
        end,
        nil
      )

      start_time = System.monotonic_time()
      Telemetry.lock_verify(start_time, :warning, ["CUDA version mismatch"])

      assert_receive {:telemetry_event, ^ref, [:snakebridge, :lock, :verify], measurements,
                      metadata}

      assert is_integer(measurements.duration)
      assert metadata.result == :warning
      assert metadata.warnings == ["CUDA version mismatch"]
    end

    test "defaults to empty warnings list" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-telemetry-handler",
        [:snakebridge, :lock, :verify],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
        end,
        nil
      )

      start_time = System.monotonic_time()
      Telemetry.lock_verify(start_time, :ok)

      assert_receive {:telemetry_event, ^ref, [:snakebridge, :lock, :verify], _measurements,
                      metadata}

      assert metadata.warnings == []
    end
  end
end
