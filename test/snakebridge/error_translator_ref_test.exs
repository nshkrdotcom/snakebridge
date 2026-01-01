defmodule SnakeBridge.ErrorTranslatorRefTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.ErrorTranslator
  alias SnakeBridge.{InvalidRefError, RefNotFoundError, SessionMismatchError}

  describe "ref not found translation" do
    test "translates KeyError message to RefNotFoundError" do
      message = "Unknown SnakeBridge reference: abc123def456"

      result = ErrorTranslator.translate_message(message)

      assert %RefNotFoundError{} = result
      assert result.ref_id == "abc123def456"
    end

    test "translates RuntimeError with ref not found" do
      error = %RuntimeError{message: "Unknown SnakeBridge reference: xyz789"}

      result = ErrorTranslator.translate(error)

      assert %RefNotFoundError{} = result
      assert result.ref_id == "xyz789"
    end

    test "extracts ref_id from various message formats" do
      message = "Unknown SnakeBridge reference: deadbeef"
      result = ErrorTranslator.translate_message(message)
      assert result.ref_id == "deadbeef"
    end

    test "handles message without extractable ref_id" do
      message = "Unknown SnakeBridge reference"
      result = ErrorTranslator.translate_message(message)

      assert %RefNotFoundError{} = result
      assert result.ref_id == nil
    end
  end

  describe "session mismatch translation" do
    test "translates session mismatch message" do
      message = "SnakeBridge reference session mismatch"

      result = ErrorTranslator.translate_message(message)

      assert %SessionMismatchError{} = result
    end

    test "translates RuntimeError with session mismatch" do
      error = %RuntimeError{message: "SnakeBridge reference session mismatch"}

      result = ErrorTranslator.translate(error)

      assert %SessionMismatchError{} = result
    end

    test "preserves original message" do
      message = "SnakeBridge reference session mismatch: expected session_a, got session_b"

      result = ErrorTranslator.translate_message(message)

      assert result.message == message
    end
  end

  describe "invalid ref translation" do
    test "translates missing id message" do
      message = "SnakeBridge reference missing id"

      result = ErrorTranslator.translate_message(message)

      assert %InvalidRefError{} = result
      assert result.reason == :missing_id
    end

    test "translates invalid payload message" do
      message = "Invalid SnakeBridge reference payload"

      result = ErrorTranslator.translate_message(message)

      assert %InvalidRefError{} = result
      assert result.reason == :invalid_format
    end

    test "translates generic invalid ref message" do
      message = "Invalid SnakeBridge reference"

      result = ErrorTranslator.translate_message(message)

      assert %InvalidRefError{} = result
      assert result.reason == :unknown
    end

    test "translates RuntimeError with invalid ref" do
      error = %RuntimeError{message: "Invalid SnakeBridge reference payload"}

      result = ErrorTranslator.translate(error)

      assert %InvalidRefError{} = result
    end
  end

  describe "error priority" do
    test "ref errors take precedence over shape errors" do
      # Unlikely real message, but tests priority
      message = "Unknown SnakeBridge reference: abc123 shapes cannot be multiplied"

      result = ErrorTranslator.translate_message(message)

      assert %RefNotFoundError{} = result
    end

    test "non-ref errors still work" do
      message = "CUDA out of memory. Tried to allocate 1024 MiB"

      result = ErrorTranslator.translate_message(message)

      refute match?(%RefNotFoundError{}, result)
      refute match?(%SessionMismatchError{}, result)
      refute match?(%InvalidRefError{}, result)
    end

    test "returns nil for unrecognized messages" do
      message = "Some random Python error"

      result = ErrorTranslator.translate_message(message)

      assert result == nil
    end
  end

  describe "translate/2 with traceback" do
    test "adds traceback to translated ref error" do
      error = %RuntimeError{message: "Unknown SnakeBridge reference: abc123"}
      traceback = "Traceback (most recent call last):\n  File..."

      result = ErrorTranslator.translate(error, traceback)

      assert %RefNotFoundError{} = result
      assert result.python_traceback == traceback
    end
  end
end
