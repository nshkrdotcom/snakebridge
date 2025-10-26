defmodule SnakebridgeTest do
  use ExUnit.Case
  doctest Snakebridge

  test "greets the world" do
    assert Snakebridge.hello() == :world
  end
end
