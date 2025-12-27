defmodule SnakeBridge.IntrospectionErrorTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.IntrospectionError

  test "classifies ModuleNotFoundError" do
    output = "Traceback...\nModuleNotFoundError: No module named 'numpy'"

    error = IntrospectionError.from_python_output(output, "numpy")

    assert error.type == :package_not_found
    assert error.package == "numpy"
    assert error.suggestion == "Run: mix snakebridge.setup"
  end

  test "classifies ImportError with message" do
    output = "ImportError: cannot import name 'cuda' from 'torch'"

    error = IntrospectionError.from_python_output(output, "torch")

    assert error.type == :import_error
    assert error.message == "cannot import name 'cuda' from 'torch'"
  end

  test "classifies timeout errors" do
    output = "TimeoutError: introspection timed out"

    error = IntrospectionError.from_python_output(output, "numpy")

    assert error.type == :timeout
  end

  test "classifies unknown errors as introspection bugs" do
    output = "ValueError: boom"

    error = IntrospectionError.from_python_output(output, "numpy")

    assert error.type == :introspection_bug
    assert error.message == "ValueError: boom"
  end
end
