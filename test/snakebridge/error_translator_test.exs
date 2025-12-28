defmodule SnakeBridge.ErrorTranslatorTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Error.{DtypeMismatchError, OutOfMemoryError, ShapeMismatchError}
  alias SnakeBridge.ErrorTranslator

  describe "translate/1 with shape mismatch errors" do
    test "translates RuntimeError with shape mismatch message" do
      error = %RuntimeError{
        message: """
        RuntimeError: mat1 and mat2 shapes cannot be multiplied (3x4 and 5x6)
        """
      }

      result = ErrorTranslator.translate(error)

      assert %ShapeMismatchError{} = result
      assert result.operation == :matmul
      assert result.shape_a == [3, 4]
      assert result.shape_b == [5, 6]
    end

    test "translates size mismatch error" do
      error = %RuntimeError{
        message: """
        RuntimeError: The size of tensor a (4) must match the size of tensor b (5) at non-singleton dimension 1
        """
      }

      result = ErrorTranslator.translate(error)

      assert %ShapeMismatchError{} = result
      assert result.message =~ "size"
    end

    test "translates broadcast error" do
      error = %RuntimeError{
        message: """
        RuntimeError: The tensors have incompatible shapes for broadcasting: [3, 4] vs [5, 6]
        """
      }

      result = ErrorTranslator.translate(error)

      assert %ShapeMismatchError{} = result
      assert result.operation == :broadcast
    end

    test "translates dimension mismatch error" do
      error = %RuntimeError{
        message: """
        RuntimeError: Dimension out of range (expected to be in range of [-2, 1], but got 3)
        """
      }

      result = ErrorTranslator.translate(error)

      assert %ShapeMismatchError{} = result
      assert result.message =~ "Dimension"
    end
  end

  describe "translate/1 with OOM errors" do
    test "translates CUDA OOM error" do
      error = %RuntimeError{
        message: """
        RuntimeError: CUDA out of memory. Tried to allocate 8192 MiB (GPU 0; 16384 MiB total capacity; 2048 MiB already allocated)
        """
      }

      result = ErrorTranslator.translate(error)

      assert %OutOfMemoryError{} = result
      assert result.device == {:cuda, 0}
      assert result.requested_mb == 8192
      assert result.total_mb == 16_384
    end

    test "translates simple CUDA OOM error" do
      error = %RuntimeError{
        message: "torch.cuda.OutOfMemoryError: CUDA out of memory"
      }

      result = ErrorTranslator.translate(error)

      assert %OutOfMemoryError{} = result
      assert match?({:cuda, _}, result.device)
    end

    test "translates MPS OOM error" do
      error = %RuntimeError{
        message: "RuntimeError: MPS backend out of memory"
      }

      result = ErrorTranslator.translate(error)

      assert %OutOfMemoryError{} = result
      assert result.device == :mps
    end
  end

  describe "translate/1 with dtype mismatch errors" do
    test "translates dtype mismatch error" do
      error = %RuntimeError{
        message: """
        RuntimeError: expected scalar type Float but found Double
        """
      }

      result = ErrorTranslator.translate(error)

      assert %DtypeMismatchError{} = result
      assert result.expected == :float32
      assert result.got == :float64
    end

    test "translates type mismatch with torch types" do
      error = %RuntimeError{
        message: "RuntimeError: expected dtype torch.float32 but got torch.int64"
      }

      result = ErrorTranslator.translate(error)

      assert %DtypeMismatchError{} = result
      assert result.expected == :float32
      assert result.got == :int64
    end

    test "translates half precision mismatch" do
      error = %RuntimeError{
        message: "RuntimeError: expected scalar type Half but found Float"
      }

      result = ErrorTranslator.translate(error)

      assert %DtypeMismatchError{} = result
      assert result.expected == :float16
      assert result.got == :float32
    end
  end

  describe "translate/1 with unrecognized errors" do
    test "returns original error when not ML-related" do
      error = %RuntimeError{message: "Some random error"}

      result = ErrorTranslator.translate(error)

      assert result == error
    end

    test "returns original error for non-RuntimeError" do
      error = %ArgumentError{message: "bad argument"}

      result = ErrorTranslator.translate(error)

      assert result == error
    end

    test "handles nil error" do
      assert ErrorTranslator.translate(nil) == nil
    end
  end

  describe "translate/2 with traceback" do
    test "includes Python traceback in translated error" do
      error = %RuntimeError{
        message: "RuntimeError: CUDA out of memory"
      }

      traceback = """
      Traceback (most recent call last):
        File "model.py", line 42, in forward
          return self.linear(x)
      """

      result = ErrorTranslator.translate(error, traceback)

      assert %OutOfMemoryError{} = result
      assert result.python_traceback == traceback
    end
  end

  describe "translate_message/1" do
    test "translates error message string" do
      message = "mat1 and mat2 shapes cannot be multiplied (3x4 and 5x6)"

      result = ErrorTranslator.translate_message(message)

      assert %ShapeMismatchError{} = result
    end

    test "returns nil for unrecognized message" do
      message = "Some random error message"

      result = ErrorTranslator.translate_message(message)

      assert result == nil
    end
  end

  describe "dtype_from_string/1" do
    test "converts Float to :float32" do
      assert ErrorTranslator.dtype_from_string("Float") == :float32
    end

    test "converts Double to :float64" do
      assert ErrorTranslator.dtype_from_string("Double") == :float64
    end

    test "converts Half to :float16" do
      assert ErrorTranslator.dtype_from_string("Half") == :float16
    end

    test "converts Long to :int64" do
      assert ErrorTranslator.dtype_from_string("Long") == :int64
    end

    test "converts Int to :int32" do
      assert ErrorTranslator.dtype_from_string("Int") == :int32
    end

    test "converts Bool to :bool" do
      assert ErrorTranslator.dtype_from_string("Bool") == :bool
    end

    test "converts torch.float32 to :float32" do
      assert ErrorTranslator.dtype_from_string("torch.float32") == :float32
    end

    test "converts torch.float64 to :float64" do
      assert ErrorTranslator.dtype_from_string("torch.float64") == :float64
    end

    test "converts torch.int64 to :int64" do
      assert ErrorTranslator.dtype_from_string("torch.int64") == :int64
    end

    test "returns atom for unknown type" do
      assert ErrorTranslator.dtype_from_string("custom_type") == :custom_type
    end
  end
end
