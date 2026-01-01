defmodule SnakeBridge.IntrospectionVisibilityTest do
  use ExUnit.Case

  alias SnakeBridge.IntrospectionError

  # This test verifies the error formatting behavior.
  # We don't actually run introspection, just test the formatting.

  describe "IntrospectionError formatting" do
    test "formats package not found error" do
      error = %IntrospectionError{
        type: :package_not_found,
        package: "nonexistent_lib",
        message: "Package 'nonexistent_lib' not found",
        suggestion: "Run: mix snakebridge.setup"
      }

      formatted = Exception.message(error)

      assert formatted =~ "Package 'nonexistent_lib' not found"
      assert formatted =~ "mix snakebridge.setup"
    end

    test "formats import error" do
      error = %IntrospectionError{
        type: :import_error,
        package: "torch",
        message: "cannot import name 'cuda' from 'torch'",
        suggestion: "Check library dependencies"
      }

      formatted = Exception.message(error)

      assert formatted =~ "cuda"
      assert formatted =~ "Check library dependencies"
    end

    test "formats timeout error" do
      error = %IntrospectionError{
        type: :timeout,
        package: "slow_lib",
        message: "Introspection timed out",
        suggestion: "Increase introspection timeout or retry"
      }

      formatted = Exception.message(error)

      assert formatted =~ "timed out"
      assert formatted =~ "Increase introspection timeout"
    end

    test "formats introspection bug" do
      error = %IntrospectionError{
        type: :introspection_bug,
        package: "broken_lib",
        message: "Unexpected error during introspection",
        suggestion: "Please report this issue"
      }

      formatted = Exception.message(error)

      assert formatted =~ "Unexpected error"
      assert formatted =~ "report this issue"
    end

    test "handles nil suggestion" do
      error = %IntrospectionError{
        type: :package_not_found,
        package: "some_lib",
        message: "Package not found",
        suggestion: nil
      }

      formatted = Exception.message(error)

      assert formatted == "Package not found"
      refute formatted =~ "Suggestion"
    end
  end

  describe "IntrospectionError.from_python_output/2" do
    test "classifies ModuleNotFoundError" do
      output = """
      Traceback (most recent call last):
        File "introspect.py", line 1, in <module>
      ModuleNotFoundError: No module named 'nonexistent'
      """

      error = IntrospectionError.from_python_output(output, "nonexistent")

      assert error.type == :package_not_found
      assert error.package == "nonexistent"
      assert error.suggestion =~ "snakebridge.setup"
    end

    test "classifies ImportError" do
      output = """
      Traceback (most recent call last):
        File "introspect.py", line 1, in <module>
      ImportError: cannot import name 'missing' from 'some_package'
      """

      error = IntrospectionError.from_python_output(output, "some_package")

      assert error.type == :import_error
      assert error.package == "some_package"
    end

    test "classifies TimeoutError" do
      output = "TimeoutError: introspection timed out after 30 seconds"

      error = IntrospectionError.from_python_output(output, "slow_package")

      assert error.type == :timeout
      assert error.suggestion =~ "timeout"
    end

    test "classifies generic errors as introspection_bug" do
      output = "SomeUnexpectedError: something went wrong"

      error = IntrospectionError.from_python_output(output, "some_package")

      assert error.type == :introspection_bug
      assert error.suggestion =~ "report"
    end
  end

  describe "format_introspection_error/3 logic" do
    # Test the formatting logic that the compile task uses
    # This mirrors the private function in Mix.Tasks.Compile.Snakebridge

    test "formats error with struct library" do
      library = %{name: "numpy", python_name: "numpy"}
      python_module = "numpy.linalg"
      reason = %{type: :import_error, message: "Import failed", suggestion: "Check deps"}

      formatted = format_test_error(library, python_module, reason)

      assert formatted =~ "numpy"
      assert formatted =~ "numpy.linalg"
      assert formatted =~ "Import failed"
      assert formatted =~ "Check deps"
    end

    test "formats error with binary message reason" do
      library = %{name: "torch", python_name: "torch"}
      python_module = "torch"
      reason = "Simple string error"

      formatted = format_test_error(library, python_module, reason)

      assert formatted =~ "torch"
      assert formatted =~ "Simple string error"
    end

    test "formats error with map message only" do
      library = %{name: "test_lib", python_name: "test_lib"}
      python_module = "test_lib"
      reason = %{message: "Some error occurred"}

      formatted = format_test_error(library, python_module, reason)

      assert formatted =~ "Some error occurred"
    end

    test "handles non-map library" do
      library = "just_a_string"
      python_module = "module"
      reason = "Error message"

      formatted = format_test_error(library, python_module, reason)

      assert formatted =~ "just_a_string"
    end
  end

  # Helper function that mirrors the private format_introspection_error/3
  defp format_test_error(library, python_module, reason) do
    library_name = get_library_name(library)
    base = build_base_message(library_name, python_module)
    format_reason(base, reason)
  end

  defp get_library_name(library) when is_map(library), do: library.name || library.python_name
  defp get_library_name(library), do: inspect(library)

  defp build_base_message(library_name, python_module) do
    base = "  [warning] Introspection failed for #{library_name}"

    if python_module && python_module != library_name do
      base <> ".#{python_module}"
    else
      base
    end
  end

  defp format_reason(base, %{type: _type, message: message, suggestion: suggestion}) do
    lines = [base, "    Error: #{message}"]
    lines = if suggestion, do: lines ++ ["    Suggestion: #{suggestion}"], else: lines
    Enum.join(lines, "\n")
  end

  defp format_reason(base, %{message: message}) do
    base <> "\n    Error: #{message}"
  end

  defp format_reason(base, message) when is_binary(message) do
    base <> "\n    Error: #{message}"
  end

  defp format_reason(base, reason) do
    base <> "\n    Error: #{inspect(reason)}"
  end
end
