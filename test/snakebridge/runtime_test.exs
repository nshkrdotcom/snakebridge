defmodule SnakeBridge.RuntimeTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Runtime

  # Import Mimic for mocking Snakepit
  import Mimic

  setup :verify_on_exit!

  describe "call/4 with successful responses" do
    test "encodes args, calls Snakepit, and decodes result" do
      # Mock Snakepit.execute to return a successful response
      expect(Snakepit, :execute, fn "snakebridge_call", payload, opts ->
        # Verify payload structure
        assert payload["module"] == "json"
        assert payload["function"] == "dumps"
        assert payload["obj"] == %{"hello" => "world"}

        # Verify options
        assert Keyword.get(opts, :timeout) == 60_000
        assert Keyword.get(opts, :pool) == Snakepit.Pool

        # Return mock successful response
        {:ok, %{"success" => true, "result" => "{\"hello\": \"world\"}"}}
      end)

      result = Runtime.call("json", "dumps", %{obj: %{hello: "world"}})

      assert {:ok, "{\"hello\": \"world\"}"} = result
    end

    test "handles custom timeout option" do
      expect(Snakepit, :execute, fn _tool, _payload, opts ->
        assert Keyword.get(opts, :timeout) == 5000
        {:ok, %{"success" => true, "result" => "ok"}}
      end)

      result = Runtime.call("test", "function", %{}, timeout: 5000)

      assert {:ok, "ok"} = result
    end

    test "handles session_id option" do
      expect(Snakepit, :execute, fn _tool, _payload, opts ->
        assert Keyword.get(opts, :session_id) == "test-session-123"
        {:ok, %{"success" => true, "result" => "ok"}}
      end)

      result = Runtime.call("test", "function", %{}, session_id: "test-session-123")

      assert {:ok, "ok"} = result
    end

    test "decodes complex nested result" do
      expect(Snakepit, :execute, fn _tool, _payload, _opts ->
        {:ok,
         %{
           "success" => true,
           "result" => %{
             "__type__" => "tuple",
             "elements" => ["ok", %{"count" => 42}]
           }
         }}
      end)

      result = Runtime.call("test", "complex_function", %{})

      # Note: atoms in tuples are encoded as strings and stay as strings when decoded
      assert {:ok, {"ok", %{"count" => 42}}} = result
    end

    test "handles numeric results" do
      expect(Snakepit, :execute, fn _tool, _payload, _opts ->
        {:ok, %{"success" => true, "result" => 3.14159}}
      end)

      result = Runtime.call("math", "pi", %{})

      assert {:ok, 3.14159} = result
    end

    test "handles list results" do
      expect(Snakepit, :execute, fn _tool, _payload, _opts ->
        {:ok, %{"success" => true, "result" => [1, 2, 3, 4, 5]}}
      end)

      result = Runtime.call("test", "range", %{n: 5})

      assert {:ok, [1, 2, 3, 4, 5]} = result
    end

    test "encodes and passes through complex arguments" do
      expect(Snakepit, :execute, fn _tool, payload, _opts ->
        # Verify complex args are properly encoded
        assert payload["data"] == %{
                 "__type__" => "tuple",
                 "elements" => [1, 2, 3]
               }

        {:ok, %{"success" => true, "result" => "processed"}}
      end)

      result = Runtime.call("test", "process", %{data: {1, 2, 3}})

      assert {:ok, "processed"} = result
    end
  end

  describe "call/4 with error responses" do
    test "handles Python error with success: false and error message" do
      expect(Snakepit, :execute, fn _tool, _payload, _opts ->
        {:ok,
         %{
           "success" => false,
           "error" => "ValueError: invalid input"
         }}
      end)

      result = Runtime.call("test", "failing_function", %{})

      assert {:error, "ValueError: invalid input"} = result
    end

    test "handles error with complex error data" do
      expect(Snakepit, :execute, fn _tool, _payload, _opts ->
        {:ok,
         %{
           "success" => false,
           "error" => %{
             "type" => "ValueError",
             "message" => "invalid input",
             "traceback" => ["line 1", "line 2"]
           }
         }}
      end)

      result = Runtime.call("test", "failing_function", %{})

      assert {:error,
              %{
                "type" => "ValueError",
                "message" => "invalid input",
                "traceback" => ["line 1", "line 2"]
              }} = result
    end

    test "handles response with error key only" do
      expect(Snakepit, :execute, fn _tool, _payload, _opts ->
        {:ok, %{"error" => "Something went wrong"}}
      end)

      result = Runtime.call("test", "function", %{})

      assert {:error, "Something went wrong"} = result
    end

    test "handles Snakepit.Error responses" do
      error = %Snakepit.Error{
        category: :timeout,
        message: "Request timed out",
        grpc_status: :deadline_exceeded,
        python_traceback: nil,
        details: %{timeout: 5000}
      }

      expect(Snakepit, :execute, fn _tool, _payload, _opts ->
        {:error, error}
      end)

      result = Runtime.call("test", "slow_function", %{})

      assert {:error, "Snakepit error (timeout): Request timed out"} = result
    end

    test "handles generic error tuples" do
      expect(Snakepit, :execute, fn _tool, _payload, _opts ->
        {:error,
         %Snakepit.Error{
           category: :pool,
           message: "Connection refused",
           grpc_status: :unavailable,
           python_traceback: nil,
           details: %{}
         }}
      end)

      result = Runtime.call("test", "function", %{})

      assert {:error, "Snakepit error (pool): Connection refused"} = result
    end
  end

  describe "call/4 with unexpected responses" do
    test "handles unexpected response format gracefully" do
      expect(Snakepit, :execute, fn _tool, _payload, _opts ->
        {:ok, %{"data" => "unexpected", "format" => true}}
      end)

      # Should decode the response even if format is unexpected
      result = Runtime.call("test", "function", %{})

      assert {:ok, %{"data" => "unexpected", "format" => true}} = result
    end

    test "handles nil response" do
      expect(Snakepit, :execute, fn _tool, _payload, _opts ->
        {:ok, nil}
      end)

      result = Runtime.call("test", "function", %{})

      assert {:ok, nil} = result
    end

    test "handles boolean response" do
      expect(Snakepit, :execute, fn _tool, _payload, _opts ->
        {:ok, %{"success" => true, "result" => true}}
      end)

      result = Runtime.call("test", "is_valid", %{})

      assert {:ok, true} = result
    end
  end

  describe "stream/4 with successful streaming" do
    test "calls Snakepit.execute_stream with decoded chunks" do
      expect(Snakepit, :execute_stream, fn "snakebridge_call", payload, callback, opts ->
        # Verify payload
        assert payload["module"] == "requests"
        assert payload["function"] == "iter_content"

        # Verify options
        assert Keyword.get(opts, :timeout) == 300_000

        # Simulate streaming chunks
        callback.(%{"chunk" => 1})
        callback.(%{"chunk" => 2})
        callback.(%{"chunk" => 3})

        :ok
      end)

      result =
        Runtime.stream("requests", "iter_content", %{url: "https://example.com"}, fn chunk ->
          send(self(), {:chunk, chunk})
        end)

      assert :ok = result

      # Verify chunks were received
      assert_received {:chunk, %{"chunk" => 1}}
      assert_received {:chunk, %{"chunk" => 2}}
      assert_received {:chunk, %{"chunk" => 3}}
    end

    test "decodes tagged types in chunks" do
      expect(Snakepit, :execute_stream, fn _tool, _payload, callback, _opts ->
        # Send chunk with tagged type
        callback.(%{
          "__type__" => "tuple",
          "elements" => ["status", "ok"]
        })

        :ok
      end)

      result =
        Runtime.stream("test", "stream_function", %{}, fn chunk ->
          send(self(), {:decoded_chunk, chunk})
        end)

      assert :ok = result
      # Note: atoms are encoded as strings
      assert_received {:decoded_chunk, {"status", "ok"}}
    end

    test "handles custom timeout for streaming" do
      expect(Snakepit, :execute_stream, fn _tool, _payload, _callback, opts ->
        assert Keyword.get(opts, :timeout) == 10_000
        :ok
      end)

      result =
        Runtime.stream("test", "function", %{}, fn _chunk -> :ok end, timeout: 10_000)

      assert :ok = result
    end

    test "handles session_id option for streaming" do
      expect(Snakepit, :execute_stream, fn _tool, _payload, _callback, opts ->
        assert Keyword.get(opts, :session_id) == "stream-session"
        :ok
      end)

      result =
        Runtime.stream("test", "function", %{}, fn _chunk -> :ok end,
          session_id: "stream-session"
        )

      assert :ok = result
    end
  end

  describe "stream/4 with errors" do
    test "handles Snakepit.Error in streaming" do
      error = %Snakepit.Error{
        category: :stream_error,
        message: "Stream interrupted",
        grpc_status: :cancelled,
        python_traceback: nil,
        details: %{}
      }

      expect(Snakepit, :execute_stream, fn _tool, _payload, _callback, _opts ->
        {:error, error}
      end)

      result = Runtime.stream("test", "function", %{}, fn _chunk -> :ok end)

      assert {:error, "Snakepit error (stream_error): Stream interrupted"} = result
    end

    test "handles generic error in streaming" do
      expect(Snakepit, :execute_stream, fn _tool, _payload, _callback, _opts ->
        {:error,
         %Snakepit.Error{
           category: :grpc_error,
           message: "Network error",
           grpc_status: :unavailable,
           python_traceback: nil,
           details: %{}
         }}
      end)

      result = Runtime.stream("test", "function", %{}, fn _chunk -> :ok end)

      assert {:error, "Snakepit error (grpc_error): Network error"} = result
    end
  end

  describe "argument encoding" do
    test "encodes empty args as empty map" do
      expect(Snakepit, :execute, fn _tool, payload, _opts ->
        # Args should be empty map when not provided
        refute Map.has_key?(payload, "args")
        {:ok, %{"success" => true, "result" => "ok"}}
      end)

      Runtime.call("test", "function")
    end

    test "encodes atoms to strings in args" do
      expect(Snakepit, :execute, fn _tool, payload, _opts ->
        assert payload["status"] == "active"
        {:ok, %{"success" => true, "result" => "ok"}}
      end)

      Runtime.call("test", "function", %{status: :active})
    end

    test "encodes DateTime in args" do
      {:ok, dt, _} = DateTime.from_iso8601("2024-01-15T10:30:00Z")

      expect(Snakepit, :execute, fn _tool, payload, _opts ->
        assert payload["timestamp"] == %{
                 "__type__" => "datetime",
                 "value" => "2024-01-15T10:30:00Z"
               }

        {:ok, %{"success" => true, "result" => "ok"}}
      end)

      Runtime.call("test", "function", %{timestamp: dt})
    end

    test "encodes MapSet in args" do
      expect(Snakepit, :execute, fn _tool, payload, _opts ->
        assert payload["items"]["__type__"] == "set"
        assert Enum.sort(payload["items"]["elements"]) == [1, 2, 3]
        {:ok, %{"success" => true, "result" => "ok"}}
      end)

      Runtime.call("test", "function", %{items: MapSet.new([1, 2, 3])})
    end
  end

  describe "result decoding" do
    test "decodes tuple results" do
      expect(Snakepit, :execute, fn _tool, _payload, _opts ->
        {:ok,
         %{
           "success" => true,
           "result" => %{
             "__type__" => "tuple",
             "elements" => [1, 2, 3]
           }
         }}
      end)

      result = Runtime.call("test", "function", %{})

      assert {:ok, {1, 2, 3}} = result
    end

    test "decodes set results" do
      expect(Snakepit, :execute, fn _tool, _payload, _opts ->
        {:ok,
         %{
           "success" => true,
           "result" => %{
             "__type__" => "set",
             "elements" => [3, 1, 2]
           }
         }}
      end)

      result = Runtime.call("test", "function", %{})

      assert {:ok, mapset} = result
      assert MapSet.equal?(mapset, MapSet.new([1, 2, 3]))
    end

    test "decodes datetime results" do
      expect(Snakepit, :execute, fn _tool, _payload, _opts ->
        {:ok,
         %{
           "success" => true,
           "result" => %{
             "__type__" => "datetime",
             "value" => "2024-01-15T10:30:00Z"
           }
         }}
      end)

      result = Runtime.call("test", "function", %{})

      assert {:ok, %DateTime{} = dt} = result
      assert DateTime.to_iso8601(dt) == "2024-01-15T10:30:00Z"
    end

    test "decodes binary results" do
      binary_data = <<255, 254, 253>>
      encoded = Base.encode64(binary_data)

      expect(Snakepit, :execute, fn _tool, _payload, _opts ->
        {:ok,
         %{
           "success" => true,
           "result" => %{
             "__type__" => "bytes",
             "data" => encoded
           }
         }}
      end)

      result = Runtime.call("test", "function", %{})

      assert {:ok, ^binary_data} = result
    end
  end

  describe "telemetry" do
    setup do
      # Attach a test telemetry handler
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-runtime-handler-#{inspect(ref)}",
        [:snakebridge, :runtime, :call],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("test-runtime-handler-#{inspect(ref)}")
      end)

      :ok
    end

    test "emits telemetry on successful call" do
      expect(Snakepit, :execute, fn _tool, _payload, _opts ->
        {:ok, %{"success" => true, "result" => "ok"}}
      end)

      Runtime.call("test_module", "test_function", %{})

      assert_receive {:telemetry, [:snakebridge, :runtime, :call], measurements, metadata}

      assert is_integer(measurements.duration)
      assert metadata.call_type == :call
      assert metadata.module == "test_module"
      assert metadata.function == "test_function"
      assert metadata.success == true
    end

    test "emits telemetry on failed call" do
      expect(Snakepit, :execute, fn _tool, _payload, _opts ->
        {:ok, %{"success" => false, "error" => "test error"}}
      end)

      Runtime.call("test_module", "test_function", %{})

      assert_receive {:telemetry, [:snakebridge, :runtime, :call], measurements, metadata}

      assert is_integer(measurements.duration)
      assert metadata.success == false
    end

    test "emits telemetry on streaming" do
      # Attach stream handler
      ref = make_ref()

      :telemetry.attach(
        "test-stream-handler-#{inspect(ref)}",
        [:snakebridge, :runtime, :stream],
        fn event, measurements, metadata, _config ->
          send(self(), {:stream_telemetry, event, measurements, metadata})
        end,
        nil
      )

      expect(Snakepit, :execute_stream, fn _tool, _payload, _callback, _opts ->
        :ok
      end)

      Runtime.stream("test_module", "test_function", %{}, fn _chunk -> :ok end)

      assert_receive {:stream_telemetry, [:snakebridge, :runtime, :stream], measurements,
                      metadata}

      assert is_integer(measurements.duration)
      assert metadata.call_type == :stream
      assert metadata.module == "test_module"
      assert metadata.function == "test_function"
      assert metadata.success == true

      :telemetry.detach("test-stream-handler-#{inspect(ref)}")
    end
  end

  describe "integration with types" do
    test "round-trips complex data structures" do
      input_data = %{
        tuple: {1, 2, 3},
        set: MapSet.new([:a, :b, :c]),
        nested: %{
          list: [1, 2, {:ok, "result"}],
          map: %{key: :value}
        }
      }

      expect(Snakepit, :execute, fn _tool, payload, _opts ->
        # Verify encoding
        assert payload["tuple"]["__type__"] == "tuple"
        assert payload["set"]["__type__"] == "set"

        # Echo back the encoded data as result
        {:ok, %{"success" => true, "result" => payload}}
      end)

      result = Runtime.call("test", "echo", input_data)

      # Verify decoding produces equivalent data
      assert {:ok, decoded} = result
      assert decoded["tuple"] == {1, 2, 3}
      assert MapSet.equal?(decoded["set"], MapSet.new(["a", "b", "c"]))
      # Note: atoms in tuples are encoded as strings and stay as strings
      assert decoded["nested"]["list"] == [1, 2, {"ok", "result"}]
      assert decoded["nested"]["map"]["key"] == "value"
    end
  end
end
