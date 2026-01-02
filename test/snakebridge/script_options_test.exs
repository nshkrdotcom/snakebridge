defmodule SnakeBridge.ScriptOptionsTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.ScriptOptions

  test "adds default exit_mode and stop_mode when unset and no env" do
    opts = ScriptOptions.resolve([], %{})

    assert opts[:exit_mode] == :auto
    assert opts[:stop_mode] == :if_started
  end

  test "does not override explicit exit_mode" do
    opts = ScriptOptions.resolve([exit_mode: :none], %{"SNAKEPIT_SCRIPT_EXIT" => "halt"})

    assert opts[:exit_mode] == :none
  end

  test "does not override legacy halt option" do
    opts = ScriptOptions.resolve([halt: true], %{})

    assert Keyword.has_key?(opts, :exit_mode) == false
  end

  test "does not set exit_mode when SNAKEPIT_SCRIPT_EXIT is set" do
    opts = ScriptOptions.resolve([], %{"SNAKEPIT_SCRIPT_EXIT" => "none"})

    assert Keyword.has_key?(opts, :exit_mode) == false
  end

  test "does not set exit_mode when legacy halt env is truthy" do
    opts = ScriptOptions.resolve([], %{"SNAKEPIT_SCRIPT_HALT" => "true"})

    assert Keyword.has_key?(opts, :exit_mode) == false
  end

  test "treats empty SNAKEPIT_SCRIPT_EXIT as unset" do
    opts = ScriptOptions.resolve([], %{"SNAKEPIT_SCRIPT_EXIT" => "   "})

    assert opts[:exit_mode] == :auto
  end

  test "treats falsey legacy halt env as unset" do
    opts = ScriptOptions.resolve([], %{"SNAKEPIT_SCRIPT_HALT" => "false"})

    assert opts[:exit_mode] == :auto
  end

  test "does not override explicit stop_mode" do
    opts = ScriptOptions.resolve([stop_mode: :never], %{})

    assert opts[:stop_mode] == :never
  end
end
