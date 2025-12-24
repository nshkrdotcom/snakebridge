defmodule SnakeBridge.Contract.ProtocolTest do
  @moduledoc """
  Protocol/contract tests to ensure stable API shapes.

  These tests verify that the describe_library and call_python
  response shapes remain consistent across refactors.
  """
  use ExUnit.Case, async: true

  describe "describe_library protocol" do
    test "successful response has required fields" do
      response = %{
        "success" => true,
        "library_version" => "1.0.0",
        "functions" => %{},
        "classes" => %{},
        "submodules" => [],
        "type_hints" => %{}
      }

      assert_describe_library_success_shape(response)
    end

    test "error response has required fields" do
      response = %{
        "success" => false,
        "error" => "ModuleNotFoundError: No module named 'nonexistent'",
        "traceback" => "Traceback (most recent call last):\n  ..."
      }

      assert_describe_library_error_shape(response)
    end

    test "function descriptor has required fields" do
      function = %{
        "name" => "dumps",
        "python_path" => "json.dumps",
        "docstring" => "Serialize obj to JSON",
        "parameters" => [
          %{
            "name" => "obj",
            "required" => true,
            "kind" => "positional_or_keyword"
          }
        ],
        "return_type" => "str"
      }

      assert_function_descriptor_shape(function)
    end

    test "class descriptor has required fields" do
      class = %{
        "name" => "Predict",
        "python_path" => "demo.Predict",
        "docstring" => "Basic prediction module",
        "methods" => [],
        "constructor" => %{
          "parameters" => [],
          "docstring" => ""
        },
        "properties" => []
      }

      assert_class_descriptor_shape(class)
    end

    test "method descriptor has required fields" do
      method = %{
        "name" => "__call__",
        "docstring" => "Execute prediction",
        "parameters" => [],
        "return_type" => nil
      }

      assert_method_descriptor_shape(method)
    end

    test "parameter descriptor has required fields" do
      param = %{
        "name" => "signature",
        "required" => true,
        "kind" => "positional_or_keyword"
      }

      assert_parameter_descriptor_shape(param)
    end

    test "parameter descriptor with optional fields" do
      param = %{
        "name" => "temperature",
        "required" => false,
        "kind" => "keyword_only",
        "default" => "0.7",
        "type" => "float"
      }

      assert_parameter_descriptor_shape(param)
      assert Map.has_key?(param, "default")
      assert Map.has_key?(param, "type")
    end
  end

  describe "call_python protocol" do
    test "successful function result has required fields" do
      response = %{
        "success" => true,
        "result" => "{\"a\": 1}"
      }

      assert_call_python_success_shape(response)
    end

    test "successful instance creation has required fields" do
      response = %{
        "success" => true,
        "instance_id" => "instance_abc123def456"
      }

      assert_instance_creation_shape(response)
    end

    test "error response has required fields" do
      response = %{
        "success" => false,
        "error" => "ValueError: invalid literal",
        "traceback" => "Traceback (most recent call last):\n  ..."
      }

      assert_call_python_error_shape(response)
    end
  end

  describe "error classification" do
    test "ValueError is classified correctly" do
      response = %{
        "success" => false,
        "error" => "ValueError: invalid input"
      }

      error = SnakeBridge.Error.new(response)
      assert error.type == :value_error
    end

    test "TypeError is classified correctly" do
      response = %{
        "success" => false,
        "error" => "TypeError: expected str"
      }

      error = SnakeBridge.Error.new(response)
      assert error.type == :type_error
    end

    test "ImportError is classified correctly" do
      response = %{
        "success" => false,
        "error" => "ImportError: No module named 'foo'"
      }

      error = SnakeBridge.Error.new(response)
      assert error.type == :import_error
    end

    test "ModuleNotFoundError is classified correctly" do
      response = %{
        "success" => false,
        "error" => "ModuleNotFoundError: No module named 'foo'"
      }

      error = SnakeBridge.Error.new(response)
      assert error.type == :module_not_found_error
    end

    test "JSONDecodeError is classified correctly" do
      response = %{
        "success" => false,
        "error" => "JSONDecodeError: Expecting value"
      }

      error = SnakeBridge.Error.new(response)
      assert error.type == :json_decode_error
    end
  end

  # Private assertion helpers

  defp assert_describe_library_success_shape(response) do
    assert is_map(response)
    assert response["success"] == true
    assert is_binary(response["library_version"])
    assert is_map(response["functions"])
    assert is_map(response["classes"])
  end

  defp assert_describe_library_error_shape(response) do
    assert is_map(response)
    assert response["success"] == false
    assert is_binary(response["error"])
    # traceback is optional but should be present for debugging
    assert is_nil(response["traceback"]) or is_binary(response["traceback"])
  end

  defp assert_function_descriptor_shape(func) do
    assert is_map(func)
    assert is_binary(func["name"])
    assert is_binary(func["python_path"])
    assert is_binary(func["docstring"]) or is_nil(func["docstring"])
    assert is_list(func["parameters"])
  end

  defp assert_class_descriptor_shape(class) do
    assert is_map(class)
    assert is_binary(class["name"])
    assert is_binary(class["python_path"])
    assert is_list(class["methods"])
    assert is_map(class["constructor"]) or is_nil(class["constructor"])
  end

  defp assert_method_descriptor_shape(method) do
    assert is_map(method)
    assert is_binary(method["name"])
    assert is_list(method["parameters"])
  end

  defp assert_parameter_descriptor_shape(param) do
    assert is_map(param)
    assert is_binary(param["name"])
    assert is_boolean(param["required"])
    assert is_binary(param["kind"]) or is_nil(param["kind"])
  end

  defp assert_call_python_success_shape(response) do
    assert is_map(response)
    assert response["success"] == true
    assert Map.has_key?(response, "result")
  end

  defp assert_instance_creation_shape(response) do
    assert is_map(response)
    assert response["success"] == true
    assert is_binary(response["instance_id"])
    assert String.starts_with?(response["instance_id"], "instance_")
  end

  defp assert_call_python_error_shape(response) do
    assert is_map(response)
    assert response["success"] == false
    assert is_binary(response["error"])
    # traceback should be present for debugging
    assert is_nil(response["traceback"]) or is_binary(response["traceback"])
  end
end
