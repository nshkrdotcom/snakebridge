defmodule SnakeBridge.DynamicTest do
  use ExUnit.Case, async: true

  describe "Dynamic.call/4" do
    test "calls method on ref" do
      ref =
        SnakeBridge.Ref.from_wire_format(%{
          "__type__" => "ref",
          "__schema__" => 1,
          "id" => "test123",
          "session_id" => "default",
          "python_module" => "test",
          "library" => "test"
        })

      payload = SnakeBridge.Dynamic.build_call_payload(ref, :method_name, [1, 2])
      assert payload["call_type"] == "method"
      assert payload["method"] == "method_name"
      assert payload["instance"]["id"] == "test123"
    end

    test "validates ref structure" do
      invalid_ref = %{"id" => "123"}

      assert_raise ArgumentError, ~r/invalid ref/i, fn ->
        SnakeBridge.Dynamic.call(invalid_ref, :method, [])
      end
    end
  end

  describe "call_dynamic/4" do
    test "builds payload with string module path" do
      payload =
        SnakeBridge.Runtime.build_dynamic_payload(
          "numpy.linalg",
          "svd",
          [[1, 2], [3, 4]],
          full_matrices: false
        )

      assert payload["call_type"] == "dynamic"
      assert payload["module_path"] == "numpy.linalg"
      assert payload["function"] == "svd"
    end
  end
end
