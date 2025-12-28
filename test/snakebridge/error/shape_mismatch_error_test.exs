defmodule SnakeBridge.Error.ShapeMismatchErrorTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Error.ShapeMismatchError

  describe "defexception" do
    test "creates exception struct with all fields" do
      error = %ShapeMismatchError{
        operation: :matmul,
        shape_a: [3, 4],
        shape_b: [2, 5],
        expected: "[*, 4] x [4, *]",
        got: "[3, 4] x [2, 5]",
        message: "Cannot multiply matrices",
        suggestion: "Transpose B",
        python_traceback: "Traceback..."
      }

      assert error.operation == :matmul
      assert error.shape_a == [3, 4]
      assert error.shape_b == [2, 5]
      assert error.expected == "[*, 4] x [4, *]"
      assert error.got == "[3, 4] x [2, 5]"
      assert error.message == "Cannot multiply matrices"
      assert error.suggestion == "Transpose B"
      assert error.python_traceback == "Traceback..."
    end

    test "has default values for message and suggestion" do
      error = %ShapeMismatchError{operation: :add}

      assert error.message == "Shape mismatch"
      assert error.suggestion == "Check tensor shapes"
    end

    test "can be raised" do
      assert_raise ShapeMismatchError, fn ->
        raise ShapeMismatchError, operation: :matmul, shape_a: [3, 4], shape_b: [2, 5]
      end
    end
  end

  describe "message/1" do
    test "formats message with operation and shapes" do
      error = %ShapeMismatchError{
        operation: :matmul,
        shape_a: [3, 4],
        shape_b: [2, 5],
        message: "Incompatible dimensions",
        suggestion: "Check matrix dimensions"
      }

      msg = Exception.message(error)

      assert msg =~ "Shape mismatch in matmul"
      assert msg =~ "Shape A: [3, 4]"
      assert msg =~ "Shape B: [2, 5]"
      assert msg =~ "Incompatible dimensions"
      assert msg =~ "Suggestion: Check matrix dimensions"
    end

    test "includes expected and got when provided" do
      error = %ShapeMismatchError{
        operation: :broadcast,
        expected: "[1, 3, 4]",
        got: "[2, 3, 4]",
        message: "Cannot broadcast",
        suggestion: "Check shapes"
      }

      msg = Exception.message(error)

      assert msg =~ "Expected: [1, 3, 4]"
      assert msg =~ "Got: [2, 3, 4]"
    end

    test "omits nil fields" do
      error = %ShapeMismatchError{
        operation: :add,
        message: "Shapes don't match",
        suggestion: "Reshape tensors"
      }

      msg = Exception.message(error)

      refute msg =~ "Shape A:"
      refute msg =~ "Shape B:"
      refute msg =~ "Expected:"
      refute msg =~ "Got:"
    end
  end

  describe "new/2" do
    test "creates error with operation and options" do
      error = ShapeMismatchError.new(:matmul, shape_a: [3, 4], shape_b: [2, 5])

      assert error.operation == :matmul
      assert error.shape_a == [3, 4]
      assert error.shape_b == [2, 5]
    end

    test "generates default message" do
      error = ShapeMismatchError.new(:add)

      assert error.message =~ "add"
    end

    test "allows custom message and suggestion" do
      error =
        ShapeMismatchError.new(:matmul,
          message: "Custom message",
          suggestion: "Custom suggestion"
        )

      assert error.message == "Custom message"
      assert error.suggestion == "Custom suggestion"
    end

    test "stores python traceback" do
      error = ShapeMismatchError.new(:matmul, python_traceback: "Traceback...")

      assert error.python_traceback == "Traceback..."
    end
  end

  describe "generate_suggestion/3" do
    test "suggests transpose for matmul dimension mismatch" do
      suggestion = ShapeMismatchError.generate_suggestion(:matmul, [3, 4], [5, 6])

      assert suggestion =~ "columns (4)"
      assert suggestion =~ "rows (5)"
      assert suggestion =~ "transpose"
    end

    test "suggests checking compatibility when matmul dimensions match" do
      suggestion = ShapeMismatchError.generate_suggestion(:matmul, [3, 4], [4, 5])

      assert suggestion =~ "compatible"
    end

    test "suggests unsqueeze/squeeze for dimension count mismatch" do
      suggestion = ShapeMismatchError.generate_suggestion(:add, [3, 4], [3, 4, 5])

      assert suggestion =~ "dimensions"
      assert suggestion =~ "unsqueeze"
    end

    test "suggests broadcasting check for shape value mismatch" do
      suggestion = ShapeMismatchError.generate_suggestion(:add, [3, 4], [3, 5])

      assert suggestion =~ "dimension"
      assert suggestion =~ "broadcasting"
    end

    test "handles nil shapes" do
      suggestion = ShapeMismatchError.generate_suggestion(:add, nil, nil)

      assert suggestion =~ "Verify"
    end
  end
end
