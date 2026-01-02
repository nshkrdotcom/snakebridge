defmodule SnakeBridge.Generator.WriteIfChangedTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator

  describe "write_if_changed/2" do
    @describetag :tmp_dir
    test "writes file when content is new", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "new_file.ex")
      content = "defmodule New do\nend"

      result = Generator.write_if_changed(path, content)

      assert result == :written
      assert File.read!(path) == content
    end

    test "skips write when content is identical", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "existing.ex")
      content = "defmodule Existing do\nend"

      # Write initial content
      File.write!(path, content)

      result = Generator.write_if_changed(path, content)

      assert result == :unchanged
      # Content should be identical
      assert File.read!(path) == content
    end

    test "rewrites file when content differs", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "changed.ex")
      old_content = "defmodule Old do\nend"
      new_content = "defmodule New do\nend"

      File.write!(path, old_content)

      result = Generator.write_if_changed(path, new_content)

      assert result == :written
      assert File.read!(path) == new_content
    end

    test "no temp files left behind after write", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "clean.ex")
      content = "defmodule Clean do\nend"

      Generator.write_if_changed(path, content)

      # No .tmp files should exist
      tmp_files = Path.wildcard(Path.join(tmp_dir, "*.tmp*"))
      assert tmp_files == []
    end

    test "concurrent writes don't corrupt file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "concurrent.ex")

      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            content = "defmodule Concurrent#{i} do\nend"
            Generator.write_if_changed(path, content)
          end)
        end

      Task.await_many(tasks)

      # File should exist and be valid Elixir
      content = File.read!(path)
      assert content =~ "defmodule Concurrent"
      assert {:ok, _} = Code.string_to_quoted(content)
    end
  end
end
