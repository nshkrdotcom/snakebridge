defmodule SnakeBridge.GeneratorRaceConditionTest do
  use ExUnit.Case, async: false

  describe "write_if_changed" do
    test "handles concurrent writes safely" do
      path = Path.join(System.tmp_dir!(), "test_#{System.unique_integer()}.ex")

      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            SnakeBridge.Generator.write_if_changed(path, "content #{i}")
          end)
        end

      results = Task.await_many(tasks, 5000)

      assert Enum.all?(results, &(&1 in [:written, :unchanged]))
      assert File.exists?(path)
      File.rm!(path)
    end

    test "cleans up temp file on error" do
      path = "/nonexistent/path/test.ex"

      assert_raise File.Error, fn ->
        SnakeBridge.Generator.write_if_changed(path, "content")
      end

      temp_files = Path.wildcard("/nonexistent/path/*.tmp.*")
      assert temp_files == []
    end
  end
end
