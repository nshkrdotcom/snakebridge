defmodule SnakeBridge.EnvironmentErrorTest do
  use ExUnit.Case, async: true

  test "message includes suggestion when present" do
    error = %SnakeBridge.EnvironmentError{
      message: "Missing packages",
      missing_packages: ["numpy"],
      suggestion: "Run: mix snakebridge.setup"
    }

    assert Exception.message(error) ==
             "Missing packages\n\nSuggestion: Run: mix snakebridge.setup"
  end
end
