defmodule SnakeBridge.RefErrorsTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.InvalidRefError
  alias SnakeBridge.RefNotFoundError
  alias SnakeBridge.SessionMismatchError

  describe "RefNotFoundError" do
    test "creates error with ref_id and session_id" do
      error =
        RefNotFoundError.exception(
          ref_id: "abc123",
          session_id: "session_1"
        )

      assert error.ref_id == "abc123"
      assert error.session_id == "session_1"
      assert Exception.message(error) =~ "abc123"
      assert Exception.message(error) =~ "not found"
    end

    test "message includes session context" do
      error =
        RefNotFoundError.exception(
          ref_id: "ref_xyz",
          session_id: "auto_<0.123.0>_12345"
        )

      assert Exception.message(error) =~ "session"
      assert Exception.message(error) =~ "auto_<0.123.0>_12345"
    end

    test "handles nil ref_id gracefully" do
      error = RefNotFoundError.exception(session_id: "session_1")

      assert error.ref_id == nil
      assert Exception.message(error) =~ "unknown"
      assert Exception.message(error) =~ "not found"
    end

    test "handles nil session_id gracefully" do
      error = RefNotFoundError.exception(ref_id: "abc123")

      assert error.session_id == nil
      assert Exception.message(error) =~ "abc123"
      assert Exception.message(error) =~ "released, expired, or evicted"
    end

    test "allows custom message" do
      error =
        RefNotFoundError.exception(
          ref_id: "abc123",
          message: "Custom error message"
        )

      assert Exception.message(error) == "Custom error message"
    end
  end

  describe "SessionMismatchError" do
    test "creates error with expected and actual session" do
      error =
        SessionMismatchError.exception(
          ref_id: "ref_123",
          expected_session: "session_a",
          actual_session: "session_b"
        )

      assert error.expected_session == "session_a"
      assert error.actual_session == "session_b"
      assert Exception.message(error) =~ "session_a"
      assert Exception.message(error) =~ "session_b"
    end

    test "message explains session scoping" do
      error =
        SessionMismatchError.exception(
          ref_id: "ref_123",
          expected_session: "session_a",
          actual_session: "session_b"
        )

      assert Exception.message(error) =~ "cannot be shared across sessions"
    end

    test "handles nil values gracefully" do
      error = SessionMismatchError.exception([])

      assert error.ref_id == nil
      assert error.expected_session == nil
      assert error.actual_session == nil
      assert Exception.message(error) =~ "unknown"
    end

    test "allows custom message" do
      error =
        SessionMismatchError.exception(
          ref_id: "ref_123",
          message: "Custom session error"
        )

      assert Exception.message(error) == "Custom session error"
    end
  end

  describe "InvalidRefError" do
    test "creates error with atom reason" do
      error = InvalidRefError.exception(reason: :missing_id)

      assert error.reason == :missing_id
      assert Exception.message(error) =~ "missing 'id' field"
    end

    test "handles :missing_type reason" do
      error = InvalidRefError.exception(reason: :missing_type)

      assert Exception.message(error) =~ "missing '__type__' field"
    end

    test "handles :invalid_format reason" do
      error = InvalidRefError.exception(reason: :invalid_format)

      assert Exception.message(error) =~ "unrecognized payload format"
    end

    test "handles unknown atom reason" do
      error = InvalidRefError.exception(reason: :some_other_reason)

      assert Exception.message(error) =~ "some_other_reason"
    end

    test "accepts string reason" do
      error = InvalidRefError.exception(reason: "malformed payload")

      assert Exception.message(error) =~ "malformed payload"
    end

    test "handles nil reason" do
      error = InvalidRefError.exception([])

      assert error.reason == nil
      assert Exception.message(error) =~ "Invalid SnakeBridge reference"
    end

    test "allows custom message" do
      error =
        InvalidRefError.exception(
          reason: :missing_id,
          message: "Custom invalid ref error"
        )

      assert Exception.message(error) == "Custom invalid ref error"
    end
  end
end
