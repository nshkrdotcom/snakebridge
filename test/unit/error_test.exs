defmodule SnakeBridge.ErrorTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Error

  describe "Error struct" do
    test "creates error with all fields" do
      error = %Error{
        type: :value_error,
        message: "Invalid value",
        python_traceback: "Traceback (most recent call last):\n  ...",
        details: %{arg: "test"}
      }

      assert error.type == :value_error
      assert error.message == "Invalid value"
      assert error.python_traceback =~ "Traceback"
      assert error.details == %{arg: "test"}
    end

    test "creates error with minimal fields" do
      error = %Error{
        type: :unknown,
        message: "Something went wrong"
      }

      assert error.type == :unknown
      assert error.message == "Something went wrong"
      assert error.python_traceback == nil
      assert error.details == nil
    end
  end

  describe "new/1" do
    test "creates error from map with success: false" do
      response = %{
        "success" => false,
        "error" => "ValueError: invalid literal",
        "traceback" => "Traceback (most recent call last):\n  File..."
      }

      error = Error.new(response)

      assert error.type == :value_error
      assert error.message == "ValueError: invalid literal"
      assert error.python_traceback =~ "Traceback"
    end

    test "classifies TypeError" do
      response = %{
        "success" => false,
        "error" => "TypeError: expected str, got int",
        "traceback" => "..."
      }

      error = Error.new(response)
      assert error.type == :type_error
    end

    test "classifies ImportError" do
      response = %{
        "success" => false,
        "error" => "ImportError: No module named 'nonexistent'",
        "traceback" => "..."
      }

      error = Error.new(response)
      assert error.type == :import_error
    end

    test "classifies AttributeError" do
      response = %{
        "success" => false,
        "error" => "AttributeError: module has no attribute 'foo'",
        "traceback" => "..."
      }

      error = Error.new(response)
      assert error.type == :attribute_error
    end

    test "classifies KeyError" do
      response = %{
        "success" => false,
        "error" => "KeyError: 'missing_key'",
        "traceback" => "..."
      }

      error = Error.new(response)
      assert error.type == :key_error
    end

    test "classifies IndexError" do
      response = %{
        "success" => false,
        "error" => "IndexError: list index out of range",
        "traceback" => "..."
      }

      error = Error.new(response)
      assert error.type == :index_error
    end

    test "classifies RuntimeError" do
      response = %{
        "success" => false,
        "error" => "RuntimeError: something unexpected",
        "traceback" => "..."
      }

      error = Error.new(response)
      assert error.type == :runtime_error
    end

    test "classifies ModuleNotFoundError" do
      response = %{
        "success" => false,
        "error" => "ModuleNotFoundError: No module named 'xyz'",
        "traceback" => "..."
      }

      error = Error.new(response)
      assert error.type == :module_not_found_error
    end

    test "classifies JSONDecodeError" do
      response = %{
        "success" => false,
        "error" => "JSONDecodeError: Expecting value",
        "traceback" => "..."
      }

      error = Error.new(response)
      assert error.type == :json_decode_error
    end

    test "handles unknown error types" do
      response = %{
        "success" => false,
        "error" => "SomeCustomError: custom message",
        "traceback" => "..."
      }

      error = Error.new(response)
      assert error.type == :unknown
    end

    test "handles plain string error" do
      error = Error.new("Something went wrong")

      assert error.type == :unknown
      assert error.message == "Something went wrong"
    end
  end

  describe "from_timeout/1" do
    test "creates timeout error" do
      error = Error.from_timeout(5000)

      assert error.type == :timeout
      assert error.message =~ "5000"
      assert error.details == %{timeout_ms: 5000}
    end
  end

  describe "Exception implementation" do
    test "can be raised" do
      assert_raise Error, fn ->
        raise %Error{type: :value_error, message: "test error"}
      end
    end

    test "has proper exception message" do
      error = %Error{type: :value_error, message: "bad value"}
      assert Exception.message(error) == "[value_error] bad value"
    end
  end
end
