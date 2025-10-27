defmodule Mix.Tasks.Snakebridge.DiscoverTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.Snakebridge.Discover

  @moduletag :mix_task

  setup do
    # Clean up any generated files
    on_exit(fn ->
      File.rm_rf("config/snakebridge")
    end)

    :ok
  end

  describe "run/1" do
    test "requires a module name argument" do
      assert_raise Mix.Error, ~r/Expected module name/, fn ->
        Discover.run([])
      end
    end

    test "discovers a Python module and generates config file" do
      output =
        capture_io(fn ->
          Discover.run(["dspy"])
        end)

      assert output =~ "Discovering Python library: dspy"
      assert output =~ "Config written to:"
      assert File.exists?("config/snakebridge/dspy.exs")
    end

    test "supports --output option for custom path" do
      capture_io(fn ->
        Discover.run(["dspy", "--output", "custom/path/dspy.exs"])
      end)

      assert File.exists?("custom/path/dspy.exs")
      File.rm_rf("custom")
    end

    test "supports --depth option for discovery depth" do
      output =
        capture_io(fn ->
          Discover.run(["dspy", "--depth", "3"])
        end)

      assert output =~ "Discovery depth: 3"
      assert File.exists?("config/snakebridge/dspy.exs")
    end

    test "handles discovery errors gracefully" do
      assert_raise Mix.Error, ~r/Failed to discover/, fn ->
        capture_io(fn ->
          Discover.run(["nonexistent_module"])
        end)
      end
    end

    test "generated config file is valid Elixir code" do
      capture_io(fn ->
        Discover.run(["dspy"])
      end)

      # Should be able to read and evaluate the generated file
      {config, _bindings} = Code.eval_file("config/snakebridge/dspy.exs")
      assert %SnakeBridge.Config{} = config
      assert config.python_module == "dspy"
    end

    test "supports --force to overwrite existing files" do
      # Create initial file
      capture_io(fn -> Discover.run(["dspy"]) end)

      # Corrupt the file
      File.write!("config/snakebridge/dspy.exs", "# corrupted content")

      # Try to overwrite without --force (should error)
      assert_raise Mix.Error, ~r/already exists/, fn ->
        capture_io(fn -> Discover.run(["dspy"]) end)
      end

      # File should still be corrupted
      assert File.read!("config/snakebridge/dspy.exs") == "# corrupted content"

      # Overwrite with --force (should succeed and regenerate)
      capture_io(fn -> Discover.run(["dspy", "--force"]) end)

      # File should be regenerated, not corrupted
      regenerated = File.read!("config/snakebridge/dspy.exs")
      assert regenerated =~ "SnakeBridge.Config"
      refute regenerated =~ "# corrupted content"
    end
  end
end
