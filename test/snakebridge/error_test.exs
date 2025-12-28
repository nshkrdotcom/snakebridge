defmodule SnakeBridge.ErrorTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Error

  describe "ShapeMismatchError alias" do
    test "Error.ShapeMismatchError is aliased correctly" do
      error = Error.ShapeMismatchError.new(:matmul, shape_a: [3, 4], shape_b: [2, 5])

      assert error.operation == :matmul
      assert error.shape_a == [3, 4]
      assert error.shape_b == [2, 5]
    end
  end

  describe "OutOfMemoryError alias" do
    test "Error.OutOfMemoryError is aliased correctly" do
      error = Error.OutOfMemoryError.new({:cuda, 0})

      assert error.device == {:cuda, 0}
    end
  end

  describe "DtypeMismatchError alias" do
    test "Error.DtypeMismatchError is aliased correctly" do
      error = Error.DtypeMismatchError.new(:float32, :float64)

      assert error.expected == :float32
      assert error.got == :float64
    end
  end

  describe "error type introspection" do
    test "all error types are exceptions" do
      assert Exception.exception?(Error.ShapeMismatchError.exception([]))
      assert Exception.exception?(Error.OutOfMemoryError.exception([]))
      assert Exception.exception?(Error.DtypeMismatchError.exception([]))
    end

    test "error messages are strings" do
      shape_error = Error.ShapeMismatchError.new(:matmul)
      oom_error = Error.OutOfMemoryError.new({:cuda, 0})
      dtype_error = Error.DtypeMismatchError.new(:float32, :float64)

      assert is_binary(Exception.message(shape_error))
      assert is_binary(Exception.message(oom_error))
      assert is_binary(Exception.message(dtype_error))
    end
  end
end
