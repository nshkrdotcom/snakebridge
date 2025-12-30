defmodule SnakeBridge.DynamicExceptionTest do
  use ExUnit.Case, async: true

  describe "dynamic exception creation" do
    test "creates exception from Python class name" do
      exception = SnakeBridge.DynamicException.create("ValueError", "invalid value")

      assert exception.__struct__ == SnakeBridge.DynamicException.ValueError
      assert Exception.message(exception) == "invalid value"
    end

    test "handles nested class names" do
      exception =
        SnakeBridge.DynamicException.create(
          "requests.exceptions.HTTPError",
          "404 Not Found"
        )

      assert exception.__struct__ == SnakeBridge.DynamicException.HTTPError
    end

    test "exception implements Exception protocol" do
      exception = SnakeBridge.DynamicException.create("CustomError", "test")

      assert Exception.exception?(exception)
      assert is_binary(Exception.message(exception))
    end
  end
end
