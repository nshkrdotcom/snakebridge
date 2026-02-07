defmodule SnakeBridge.RuntimeErrorModeTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    restore = SnakeBridge.TestHelpers.put_runtime_client(SnakeBridge.RuntimeClientMock)
    original_error_mode = Application.get_env(:snakebridge, :error_mode)

    on_exit(fn ->
      if is_nil(original_error_mode) do
        Application.delete_env(:snakebridge, :error_mode)
      else
        Application.put_env(:snakebridge, :error_mode, original_error_mode)
      end
    end)

    on_exit(restore)

    :ok
  end

  defmodule NumpyLinalg do
    def __snakebridge_python_name__, do: "numpy.linalg"
  end

  test "translated error_mode maps Python errors to structured errors" do
    Application.put_env(:snakebridge, :error_mode, :translated)

    reason = %{
      message: "CUDA out of memory",
      python_type: "RuntimeError",
      python_traceback: "traceback"
    }

    expect(SnakeBridge.RuntimeClientMock, :execute, fn _tool, _payload, _opts ->
      {:error, reason}
    end)

    assert {:error, %SnakeBridge.Error.OutOfMemoryError{python_traceback: "traceback"}} =
             SnakeBridge.Runtime.call(NumpyLinalg, :solve, [1, 2])
  end

  test "translated error_mode unwraps Snakepit.Error details.reason payloads" do
    Application.put_env(:snakebridge, :error_mode, :translated)

    reason =
      wrapped_reason(%{
        message: "Unexpected value",
        python_type: "ValueError",
        python_traceback: "traceback"
      })

    expect(SnakeBridge.RuntimeClientMock, :execute, fn _tool, _payload, _opts ->
      {:error, reason}
    end)

    assert {:error, exception} = SnakeBridge.Runtime.call(NumpyLinalg, :solve, [1, 2])
    assert exception.__struct__ == SnakeBridge.DynamicException.get_or_create_module("ValueError")
    assert Map.get(exception, :python_traceback) == "traceback"
  end

  test "raise_translated error_mode raises for translated errors" do
    Application.put_env(:snakebridge, :error_mode, :raise_translated)

    reason = %{
      message: "CUDA out of memory",
      python_type: "RuntimeError",
      python_traceback: "traceback"
    }

    expect(SnakeBridge.RuntimeClientMock, :execute, fn _tool, _payload, _opts ->
      {:error, reason}
    end)

    assert_raise SnakeBridge.Error.OutOfMemoryError, fn ->
      SnakeBridge.Runtime.call(NumpyLinalg, :solve, [1, 2])
    end
  end

  test "raise_translated error_mode raises for dynamic Python errors" do
    Application.put_env(:snakebridge, :error_mode, :raise_translated)

    reason = %{message: "Unexpected value", python_type: "ValueError"}

    expect(SnakeBridge.RuntimeClientMock, :execute, fn _tool, _payload, _opts ->
      {:error, reason}
    end)

    assert_raise SnakeBridge.DynamicException.ValueError, fn ->
      SnakeBridge.Runtime.call(NumpyLinalg, :solve, [1, 2])
    end
  end

  test "raise_translated error_mode raises for wrapped Snakepit.Error reasons" do
    Application.put_env(:snakebridge, :error_mode, :raise_translated)

    nested_reason = %Snakepit.Error.ValueError{
      message: "invalid literal for int() with base 10: 'not-a-number'",
      python_type: "ValueError",
      python_traceback: "traceback"
    }

    reason = wrapped_reason(nested_reason)

    expect(SnakeBridge.RuntimeClientMock, :execute, fn _tool, _payload, _opts ->
      {:error, reason}
    end)

    assert_raise SnakeBridge.DynamicException.ValueError, fn ->
      SnakeBridge.Runtime.call(NumpyLinalg, :solve, [1, 2])
    end
  end

  defp wrapped_reason(inner_reason) do
    %Snakepit.Error{
      category: :worker,
      message: "Request failed",
      details: %{
        command: "snakebridge.call",
        reason: inner_reason
      }
    }
  end
end
