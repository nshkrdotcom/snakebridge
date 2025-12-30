defmodule SnakeBridge.RuntimeContractTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    original = Application.get_env(:snakebridge, :runtime_client)

    # Clear auto-session for consistent test behavior
    SnakeBridge.Runtime.clear_auto_session()

    on_exit(fn ->
      if original do
        Application.put_env(:snakebridge, :runtime_client, original)
      else
        Application.delete_env(:snakebridge, :runtime_client)
      end
    end)

    :ok
  end

  defmodule NumpyLinalg do
    def __snakebridge_python_name__, do: "numpy.linalg"
  end

  defmodule SympySymbol do
    def __snakebridge_python_name__, do: "sympy"
    def __snakebridge_python_class__, do: "Symbol"
  end

  describe "call/4" do
    test "builds payload with required fields and uses runtime_client override" do
      Application.put_env(:snakebridge, :runtime_client, SnakeBridge.RuntimeClientMock)

      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, _opts ->
        # Check core fields (session_id is now always present via auto-session)
        assert payload["protocol_version"] == 1
        assert payload["min_supported_version"] == 1
        assert payload["library"] == "numpy"
        assert payload["python_module"] == "numpy.linalg"
        assert payload["function"] == "solve"
        assert payload["args"] == [1, 2]
        assert payload["kwargs"] == %{"axis" => 0}
        assert payload["idempotent"] == false
        # session_id is now always present
        assert is_binary(payload["session_id"])

        {:ok, :ok}
      end)

      assert {:ok, :ok} =
               SnakeBridge.Runtime.call(NumpyLinalg, :solve, [1, 2], axis: 0)
    end
  end

  describe "call_class/4" do
    test "includes call_type and kwargs in payload" do
      Application.put_env(:snakebridge, :runtime_client, SnakeBridge.RuntimeClientMock)

      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.call", payload, _opts ->
        # Check core fields (session_id is now always present via auto-session)
        assert payload["protocol_version"] == 1
        assert payload["min_supported_version"] == 1
        assert payload["call_type"] == "class"
        assert payload["library"] == "sympy"
        assert payload["python_module"] == "sympy"
        assert payload["class"] == "Symbol"
        assert payload["function"] == "__init__"
        assert payload["args"] == ["x"]
        assert payload["kwargs"] == %{}
        assert payload["idempotent"] == false
        # session_id is now always present
        assert is_binary(payload["session_id"])

        {:ok, :ok}
      end)

      assert {:ok, :ok} =
               SnakeBridge.Runtime.call_class(SympySymbol, :__init__, ["x"])
    end
  end

  describe "stream/5" do
    test "routes through snakebridge.stream" do
      Application.put_env(:snakebridge, :runtime_client, SnakeBridge.RuntimeClientMock)

      expect(SnakeBridge.RuntimeClientMock, :execute_stream, fn "snakebridge.stream",
                                                                payload,
                                                                _cb,
                                                                _opts ->
        assert payload["library"] == "numpy"
        assert payload["python_module"] == "numpy.linalg"
        assert payload["function"] == "solve"
        assert payload["kwargs"] == %{}
        assert payload["idempotent"] == false
        assert payload["protocol_version"] == 1
        assert payload["min_supported_version"] == 1

        :ok
      end)

      assert :ok =
               SnakeBridge.Runtime.stream(NumpyLinalg, :solve, [1, 2], fn _chunk -> :ok end)
    end
  end

  describe "release_ref/2" do
    test "sends protocol payload and returns :ok" do
      Application.put_env(:snakebridge, :runtime_client, SnakeBridge.RuntimeClientMock)

      ref =
        SnakeBridge.Ref.from_wire_format(%{
          "__type__" => "ref",
          "__schema__" => 1,
          "id" => "ref-1",
          "session_id" => "session-1",
          "python_module" => "sympy",
          "library" => "sympy"
        })

      wire_ref = SnakeBridge.Ref.to_wire_format(ref)

      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.release_ref",
                                                         payload,
                                                         _opts ->
        assert payload == %{
                 "protocol_version" => 1,
                 "min_supported_version" => 1,
                 "ref" => wire_ref
               }

        {:ok, :released}
      end)

      assert :ok = SnakeBridge.Runtime.release_ref(ref)
    end
  end

  describe "release_session/2" do
    test "sends protocol payload and returns :ok" do
      Application.put_env(:snakebridge, :runtime_client, SnakeBridge.RuntimeClientMock)

      expect(SnakeBridge.RuntimeClientMock, :execute, fn "snakebridge.release_session",
                                                         payload,
                                                         _opts ->
        assert payload == %{
                 "protocol_version" => 1,
                 "min_supported_version" => 1,
                 "session_id" => "session-1"
               }

        {:ok, :released}
      end)

      assert :ok = SnakeBridge.Runtime.release_session("session-1")
    end
  end

  describe "normalize_args_opts/2" do
    test "moves keyword args into opts when opts are empty" do
      assert {[], [axis: 0]} = SnakeBridge.Runtime.normalize_args_opts([axis: 0], [])
    end

    test "keeps args when opts are provided" do
      args = [axis: 0]
      opts = [timeout: 1]

      assert {^args, ^opts} = SnakeBridge.Runtime.normalize_args_opts(args, opts)
    end

    test "keeps non-keyword args" do
      assert {[1, 2], []} = SnakeBridge.Runtime.normalize_args_opts([1, 2], [])
    end
  end
end
