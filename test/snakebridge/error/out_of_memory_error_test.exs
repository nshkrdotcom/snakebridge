defmodule SnakeBridge.Error.OutOfMemoryErrorTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Error.OutOfMemoryError

  describe "defexception" do
    test "creates exception struct with all fields" do
      error = %OutOfMemoryError{
        device: {:cuda, 0},
        requested_mb: 8192,
        available_mb: 2048,
        total_mb: 16_384,
        message: "CUDA OOM",
        suggestions: ["Reduce batch size"],
        python_traceback: "Traceback..."
      }

      assert error.device == {:cuda, 0}
      assert error.requested_mb == 8192
      assert error.available_mb == 2048
      assert error.total_mb == 16_384
      assert error.message == "CUDA OOM"
      assert error.suggestions == ["Reduce batch size"]
      assert error.python_traceback == "Traceback..."
    end

    test "has default values" do
      error = %OutOfMemoryError{device: {:cuda, 0}}

      assert error.message == "Out of memory"
      assert error.suggestions == []
    end

    test "can be raised" do
      assert_raise OutOfMemoryError, fn ->
        raise OutOfMemoryError, device: {:cuda, 0}
      end
    end
  end

  describe "message/1" do
    test "formats message with CUDA device" do
      error = %OutOfMemoryError{
        device: {:cuda, 0},
        requested_mb: 8192,
        available_mb: 2048,
        total_mb: 16_384,
        message: "CUDA out of memory",
        suggestions: []
      }

      msg = Exception.message(error)

      assert msg =~ "GPU Out of Memory on CUDA:0"
      assert msg =~ "Requested: 8192 MB"
      assert msg =~ "Available: 2048 MB"
      assert msg =~ "Total: 16384 MB"
    end

    test "formats message with MPS device" do
      error = %OutOfMemoryError{
        device: :mps,
        message: "MPS out of memory",
        suggestions: []
      }

      msg = Exception.message(error)

      assert msg =~ "Apple MPS"
    end

    test "formats message with CPU" do
      error = %OutOfMemoryError{
        device: :cpu,
        message: "CPU out of memory",
        suggestions: []
      }

      msg = Exception.message(error)

      assert msg =~ "CPU"
    end

    test "includes default suggestions for CUDA" do
      error = %OutOfMemoryError{
        device: {:cuda, 0},
        message: "OOM",
        suggestions: []
      }

      msg = Exception.message(error)

      assert msg =~ "Reduce batch size"
      assert msg =~ "gradient checkpointing"
      assert msg =~ "mixed precision"
      assert msg =~ "Move some operations to CPU"
    end

    test "includes custom suggestions" do
      error = %OutOfMemoryError{
        device: {:cuda, 0},
        message: "OOM",
        suggestions: ["Custom suggestion"]
      }

      msg = Exception.message(error)

      assert msg =~ "Custom suggestion"
    end

    test "shows unknown for nil memory values" do
      error = %OutOfMemoryError{
        device: {:cuda, 0},
        requested_mb: 8192,
        available_mb: nil,
        total_mb: nil,
        message: "OOM",
        suggestions: []
      }

      msg = Exception.message(error)

      assert msg =~ "Requested: 8192 MB"
      assert msg =~ "Available: unknown MB"
      assert msg =~ "Total: unknown MB"
    end

    test "omits memory info section when all values are nil" do
      error = %OutOfMemoryError{
        device: {:cuda, 0},
        requested_mb: nil,
        available_mb: nil,
        total_mb: nil,
        message: "OOM",
        suggestions: []
      }

      msg = Exception.message(error)

      refute msg =~ "Memory Info:"
    end
  end

  describe "new/2" do
    test "creates error with device" do
      error = OutOfMemoryError.new({:cuda, 0})

      assert error.device == {:cuda, 0}
    end

    test "creates error with memory info" do
      error =
        OutOfMemoryError.new({:cuda, 0},
          requested_mb: 8192,
          available_mb: 2048,
          total_mb: 16_384
        )

      assert error.requested_mb == 8192
      assert error.available_mb == 2048
      assert error.total_mb == 16_384
    end

    test "generates default message" do
      error = OutOfMemoryError.new({:cuda, 0})

      assert error.message =~ "CUDA:0"
    end

    test "allows custom message and suggestions" do
      error =
        OutOfMemoryError.new({:cuda, 0},
          message: "Custom message",
          suggestions: ["Custom suggestion"]
        )

      assert error.message == "Custom message"
      assert error.suggestions == ["Custom suggestion"]
    end

    test "stores python traceback" do
      error = OutOfMemoryError.new({:cuda, 0}, python_traceback: "Traceback...")

      assert error.python_traceback == "Traceback..."
    end
  end
end
