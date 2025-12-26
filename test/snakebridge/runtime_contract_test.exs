defmodule SnakeBridge.RuntimeContractTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    original = Application.get_env(:snakebridge, :runtime_client)

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
        assert payload == %{
                 "library" => "numpy",
                 "python_module" => "numpy.linalg",
                 "function" => "solve",
                 "args" => [1, 2],
                 "kwargs" => %{"axis" => 0},
                 "idempotent" => false
               }

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
        assert payload == %{
                 "call_type" => "class",
                 "library" => "sympy",
                 "python_module" => "sympy",
                 "class" => "Symbol",
                 "function" => "__init__",
                 "args" => ["x"],
                 "kwargs" => %{},
                 "idempotent" => false
               }

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

        :ok
      end)

      assert :ok =
               SnakeBridge.Runtime.stream(NumpyLinalg, :solve, [1, 2], fn _chunk -> :ok end)
    end
  end
end
