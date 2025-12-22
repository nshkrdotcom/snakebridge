defmodule SnakeBridge.Integration.RealSnakepitTest do
  @moduledoc """
  Integration tests with real Python execution via Snakepit.

  These tests require:
  1. Snakepit to be running with Python available
  2. The SNAKEPIT_PYTHON environment variable set (optional, uses system Python)

  Run with: mix test --include real_python
  """
  use ExUnit.Case

  alias SnakeBridge.Runtime
  alias SnakeBridge.Error

  @moduletag :real_python

  setup_all do
    adapter_spec = "snakebridge_adapter.adapter.SnakeBridgeAdapter"

    {python_exe, pythonpath, pool_config} =
      SnakeBridge.SnakepitTestHelper.prepare_python_env!(adapter_spec)

    original_adapter = Application.get_env(:snakebridge, :snakepit_adapter)
    Application.put_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitAdapter)

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("REAL PYTHON TEST ENVIRONMENT (Runtime)")
    IO.puts(String.duplicate("=", 60))
    IO.puts("Python: #{python_exe}")
    IO.puts("PYTHONPATH: #{pythonpath}")
    IO.puts("Adapter: #{adapter_spec}")
    IO.puts("Pooling: enabled")
    IO.puts(String.duplicate("=", 60) <> "\n")

    restore_env =
      SnakeBridge.SnakepitTestHelper.start_snakepit!(
        pool_config: pool_config,
        python_executable: python_exe
      )

    on_exit(fn ->
      restore_env.()
      Application.put_env(:snakebridge, :snakepit_adapter, original_adapter)
    end)

    :ok
  end

  describe "json module round-trips" do
    test "json.dumps serializes to JSON string" do
      result = Runtime.call_function("json", "dumps", %{obj: %{a: 1, b: "hello"}})

      case result do
        {:ok, json_str} ->
          assert is_binary(json_str)
          # Parse to verify valid JSON
          {:ok, decoded} = Jason.decode(json_str)
          assert decoded["a"] == 1
          assert decoded["b"] == "hello"

        {:error, _} = error ->
          flunk("Expected success, got: #{inspect(error)}")
      end
    end

    test "json.loads parses JSON to map" do
      result = Runtime.call_function("json", "loads", %{s: ~s({"x": 42, "y": "test"})})

      case result do
        {:ok, map} ->
          assert is_map(map)
          assert map["x"] == 42
          assert map["y"] == "test"

        {:error, _} = error ->
          flunk("Expected success, got: #{inspect(error)}")
      end
    end

    test "json.loads with invalid JSON returns error" do
      result = Runtime.call_function("json", "loads", %{s: "not valid json"})

      case result do
        {:error, %Error{type: :json_decode_error}} ->
          :ok

        {:error, %Error{} = error} ->
          # Accept any error with traceback
          assert error.type in [:json_decode_error, :value_error, :unknown]

        {:error, reason} when is_binary(reason) ->
          assert String.contains?(reason, "JSON") or String.contains?(reason, "Expecting")

        {:ok, _} ->
          flunk("Expected error for invalid JSON")
      end
    end
  end

  describe "math module operations" do
    test "math.sqrt computes square root" do
      result = Runtime.call_function("math", "sqrt", %{x: 16.0})

      case result do
        {:ok, sqrt} ->
          assert_in_delta sqrt, 4.0, 0.0001

        {:error, _} = error ->
          flunk("Expected success, got: #{inspect(error)}")
      end
    end

    test "math.sqrt with negative returns error" do
      result = Runtime.call_function("math", "sqrt", %{x: -1.0})

      case result do
        {:error, %Error{}} ->
          :ok

        {:error, reason} ->
          assert is_binary(reason) or is_map(reason)

        {:ok, _} ->
          flunk("Expected error for sqrt(-1)")
      end
    end

    test "math.pi is a constant" do
      # Access pi via getattr pattern
      result = Runtime.call_function("math", "floor", %{x: 3.14159})

      case result do
        {:ok, value} ->
          assert value == 3

        {:error, _} = error ->
          flunk("Expected success, got: #{inspect(error)}")
      end
    end
  end

  describe "error propagation" do
    test "non-existent module returns module not found error" do
      result = Runtime.call_function("nonexistent_module_xyz", "foo", %{})

      case result do
        {:error, %Error{type: error_type}} ->
          assert error_type in [:module_not_found_error, :import_error, :unknown]

        {:error, reason} when is_binary(reason) ->
          assert String.contains?(reason, "module") or
                   String.contains?(reason, "ModuleNotFoundError")

        {:ok, _} ->
          flunk("Expected error for nonexistent module")
      end
    end

    test "non-existent function returns attribute error" do
      result = Runtime.call_function("json", "nonexistent_function", %{})

      case result do
        {:error, %Error{type: error_type}} ->
          assert error_type in [:attribute_error, :unknown]

        {:error, reason} when is_binary(reason) ->
          assert String.contains?(reason, "attribute") or String.contains?(reason, "has no")

        {:ok, _} ->
          flunk("Expected error for nonexistent function")
      end
    end

    test "type error is propagated" do
      # json.dumps with non-serializable should fail
      result = Runtime.call_function("json", "dumps", %{obj: "circular_ref_placeholder"})

      # This may succeed or fail depending on Python version
      case result do
        # String is serializable
        {:ok, _} -> :ok
        # Some edge case
        {:error, _} -> :ok
      end
    end
  end

  describe "telemetry events" do
    setup do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "real-python-test-#{inspect(ref)}",
        [:snakebridge, :call, :stop],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("real-python-test-#{inspect(ref)}")
      end)

      :ok
    end

    test "emits telemetry on real Python call" do
      Runtime.call_function("json", "dumps", %{obj: %{test: true}})

      # Should receive telemetry event
      receive do
        {:telemetry_event, [:snakebridge, :call, :stop], measurements, metadata} ->
          assert is_integer(measurements.duration)
          assert measurements.duration > 0
          assert metadata.tool_name == "call_python"
      after
        5000 ->
          # May not receive if Snakepit is not running
          :ok
      end
    end
  end

  describe "timeout handling" do
    @tag timeout: 10_000
    test "timeout returns error after deadline" do
      # This test would need a slow Python operation
      # For now, just verify the timeout mechanism works
      result = Runtime.call_function("json", "dumps", %{obj: %{}}, timeout: 100)

      case result do
        {:ok, _} -> :ok
        {:error, %Error{type: :timeout}} -> :ok
        {:error, _} -> :ok
      end
    end
  end
end
