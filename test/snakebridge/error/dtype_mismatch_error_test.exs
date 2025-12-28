defmodule SnakeBridge.Error.DtypeMismatchErrorTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Error.DtypeMismatchError

  describe "defexception" do
    test "creates exception struct with all fields" do
      error = %DtypeMismatchError{
        expected: :float32,
        got: :float64,
        operation: :matmul,
        message: "Types don't match",
        suggestion: "Convert tensor",
        python_traceback: "Traceback..."
      }

      assert error.expected == :float32
      assert error.got == :float64
      assert error.operation == :matmul
      assert error.message == "Types don't match"
      assert error.suggestion == "Convert tensor"
      assert error.python_traceback == "Traceback..."
    end

    test "has default values" do
      error = %DtypeMismatchError{expected: :float32, got: :float64}

      assert error.message == "Dtype mismatch"
      assert error.suggestion == "Convert tensor to the expected dtype"
    end

    test "can be raised" do
      assert_raise DtypeMismatchError, fn ->
        raise DtypeMismatchError, expected: :float32, got: :float64
      end
    end
  end

  describe "message/1" do
    test "formats message with operation" do
      error = %DtypeMismatchError{
        expected: :float32,
        got: :float64,
        operation: :matmul,
        message: "Cannot multiply",
        suggestion: "Convert to float32"
      }

      msg = Exception.message(error)

      assert msg =~ "Dtype mismatch in matmul"
      assert msg =~ "Expected: float32"
      assert msg =~ "Got: float64"
      assert msg =~ "Cannot multiply"
      assert msg =~ "Suggestion: Convert to float32"
    end

    test "omits operation when nil" do
      error = %DtypeMismatchError{
        expected: :int32,
        got: :int64,
        operation: nil,
        message: "Types differ",
        suggestion: "Use int32"
      }

      msg = Exception.message(error)

      assert msg =~ "Dtype mismatch\n"
      refute msg =~ "Dtype mismatch in"
    end

    test "formats underscored dtype names correctly" do
      error = %DtypeMismatchError{
        expected: :float_16,
        got: :float_32,
        message: "Test",
        suggestion: "Test"
      }

      msg = Exception.message(error)

      assert msg =~ "float16"
      assert msg =~ "float32"
    end
  end

  describe "new/3" do
    test "creates error with expected and got dtypes" do
      error = DtypeMismatchError.new(:float32, :float64)

      assert error.expected == :float32
      assert error.got == :float64
    end

    test "creates error with operation" do
      error = DtypeMismatchError.new(:float32, :float64, operation: :matmul)

      assert error.operation == :matmul
    end

    test "generates default suggestion" do
      error = DtypeMismatchError.new(:float32, :float64)

      assert error.suggestion =~ "float32"
    end

    test "allows custom message and suggestion" do
      error =
        DtypeMismatchError.new(:float32, :float64,
          message: "Custom message",
          suggestion: "Custom suggestion"
        )

      assert error.message == "Custom message"
      assert error.suggestion == "Custom suggestion"
    end

    test "stores python traceback" do
      error = DtypeMismatchError.new(:float32, :float64, python_traceback: "Traceback...")

      assert error.python_traceback == "Traceback..."
    end
  end

  describe "generate_suggestion/2" do
    test "warns about precision loss for float64 to float32" do
      suggestion = DtypeMismatchError.generate_suggestion(:float32, :float64)

      assert suggestion =~ "float32"
      assert suggestion =~ "may lose precision"
    end

    test "warns about precision loss for float32 to float16" do
      suggestion = DtypeMismatchError.generate_suggestion(:float16, :float32)

      assert suggestion =~ "float16"
      assert suggestion =~ "may lose precision"
    end

    test "warns about precision loss for int64 to int32" do
      suggestion = DtypeMismatchError.generate_suggestion(:int32, :int64)

      assert suggestion =~ "int32"
      assert suggestion =~ "may lose precision"
    end

    test "suggests explicit conversion for float to int" do
      suggestion = DtypeMismatchError.generate_suggestion(:int32, :float32)

      assert suggestion =~ "int32"
    end

    test "suggests explicit conversion for int to float" do
      suggestion = DtypeMismatchError.generate_suggestion(:float32, :int32)

      assert suggestion =~ "float32"
    end

    test "provides basic suggestion for same-type conversion" do
      suggestion = DtypeMismatchError.generate_suggestion(:float32, :float16)

      assert suggestion =~ "float32"
    end

    test "handles unknown types" do
      suggestion = DtypeMismatchError.generate_suggestion(:bfloat16, :custom)

      assert suggestion =~ "bfloat16"
    end
  end
end
