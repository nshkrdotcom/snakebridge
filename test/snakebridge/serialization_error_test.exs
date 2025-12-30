defmodule SnakeBridge.SerializationErrorTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.SerializationError

  # Define test struct at module level
  defmodule TestStruct do
    defstruct [:field]
  end

  describe "SerializationError.exception/1" do
    test "creates exception for PID" do
      error = SerializationError.exception(value: self())

      assert error.type == :pid
      assert error.value == self()
      assert error.message =~ "Cannot serialize value of type"
      assert error.message =~ ":pid"
    end

    test "creates exception for port" do
      port = Port.open({:spawn, "cat"}, [:binary])

      try do
        error = SerializationError.exception(value: port)

        assert error.type == :port
        assert error.value == port
        assert error.message =~ ":port"
      after
        Port.close(port)
      end
    end

    test "creates exception for reference" do
      ref = make_ref()
      error = SerializationError.exception(value: ref)

      assert error.type == :reference
      assert error.value == ref
      assert error.message =~ ":reference"
    end

    test "creates exception for custom struct" do
      value = %TestStruct{field: "value"}
      error = SerializationError.exception(value: value)

      assert error.type == TestStruct
      assert error.value == value
      assert error.message =~ "TestStruct"
    end

    test "creates exception for unknown type" do
      # Using a tuple that won't match struct clause
      error = SerializationError.exception(value: {:some, :tuple})

      assert error.type == :unknown
    end

    test "message includes resolution documentation reference" do
      error = SerializationError.exception(value: self())

      assert error.message =~ "SnakeBridge.SerializationError"
      assert error.message =~ "resolution options"
    end

    test "message includes value representation" do
      error = SerializationError.exception(value: self())

      assert error.message =~ "#PID<"
    end
  end

  describe "SerializationError.new/1" do
    test "creates error with message" do
      error = SerializationError.new("custom message")

      assert error.message == "custom message"
      assert error.value == nil
      assert error.type == :unknown
    end

    test "creates error with default message" do
      error = SerializationError.new()

      assert error.message == "Arguments are not JSON-serializable"
      assert error.value == nil
      assert error.type == :unknown
    end

    test "creates error with nil message uses default" do
      error = SerializationError.new(nil)

      assert error.message == "Arguments are not JSON-serializable"
    end
  end

  describe "exception behavior" do
    test "can be raised" do
      assert_raise SerializationError, fn ->
        raise SerializationError, value: self()
      end
    end

    test "raised exception contains correct type" do
      error =
        assert_raise SerializationError, fn ->
          raise SerializationError, value: make_ref()
        end

      assert error.type == :reference
    end
  end
end
