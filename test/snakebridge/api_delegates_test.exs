defmodule SnakeBridge.ApiDelegatesTest do
  use ExUnit.Case, async: true

  describe "release_ref/1,2 delegates" do
    test "release_ref/1 is accessible from SnakeBridge module" do
      assert function_exported?(SnakeBridge, :release_ref, 1)
    end

    test "release_ref/2 is accessible from SnakeBridge module" do
      assert function_exported?(SnakeBridge, :release_ref, 2)
    end
  end

  describe "release_session/1,2 delegates" do
    test "release_session/1 is accessible from SnakeBridge module" do
      assert function_exported?(SnakeBridge, :release_session, 1)
    end

    test "release_session/2 is accessible from SnakeBridge module" do
      assert function_exported?(SnakeBridge, :release_session, 2)
    end
  end

  describe "run_as_script/1,2 delegates" do
    test "run_as_script/1 is accessible from SnakeBridge module" do
      assert function_exported?(SnakeBridge, :run_as_script, 1)
    end

    test "run_as_script/2 is accessible from SnakeBridge module" do
      assert function_exported?(SnakeBridge, :run_as_script, 2)
    end
  end
end
