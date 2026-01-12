defmodule SnakeBridge.SerializationTest do
  @moduledoc """
  Tests for SnakeBridge serialization helpers.

  These are delegates to Snakepit.Serialization, provided for ergonomic access
  so SnakeBridge users don't need to call Snakepit directly.
  """
  use ExUnit.Case, async: true

  describe "unserializable?/1" do
    test "returns true for unserializable marker" do
      marker = %{
        "__ffi_unserializable__" => true,
        "__type__" => "dspy.clients.lm.ModelResponse",
        "__repr__" => "ModelResponse(id='chatcmpl-123')"
      }

      assert SnakeBridge.unserializable?(marker) == true
    end

    test "returns false for regular map" do
      assert SnakeBridge.unserializable?(%{"key" => "value"}) == false
    end

    test "returns false for nil" do
      assert SnakeBridge.unserializable?(nil) == false
    end

    test "returns false for string" do
      assert SnakeBridge.unserializable?("string") == false
    end

    test "returns false for list" do
      assert SnakeBridge.unserializable?([1, 2, 3]) == false
    end
  end

  describe "unserializable_info/1" do
    test "returns {:ok, info} for valid marker" do
      marker = %{
        "__ffi_unserializable__" => true,
        "__type__" => "requests.models.Response",
        "__repr__" => "<Response [200]>"
      }

      assert {:ok, info} = SnakeBridge.unserializable_info(marker)
      assert info.type == "requests.models.Response"
      assert info.repr == "<Response [200]>"
    end

    test "returns :error for non-marker" do
      assert SnakeBridge.unserializable_info(%{"key" => "value"}) == :error
    end

    test "returns :error for nil" do
      assert SnakeBridge.unserializable_info(nil) == :error
    end

    test "handles marker with missing fields" do
      marker = %{"__ffi_unserializable__" => true}

      assert {:ok, info} = SnakeBridge.unserializable_info(marker)
      assert info.type == nil
      assert info.repr == nil
    end
  end

  describe "usage in typical SnakeBridge workflow" do
    test "detecting markers in returned data" do
      # Simulates data returned from a Python call
      # where some fields couldn't be serialized
      result = %{
        "status" => "success",
        "data" => [1, 2, 3],
        "metadata" => %{
          "__ffi_unserializable__" => true,
          "__type__" => "some.internal.Object",
          "__repr__" => "Object()"
        }
      }

      refute SnakeBridge.unserializable?(result)
      refute SnakeBridge.unserializable?(result["data"])
      assert SnakeBridge.unserializable?(result["metadata"])
    end
  end
end
