defmodule Mix.Tasks.Snakebridge.DiscoverTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.Snakebridge.Discover

  @moduletag :mix_task

  setup do
    # Clean up any generated files
    on_exit(fn ->
      File.rm_rf("priv/snakebridge/manifests/_drafts")
    end)

    :ok
  end

  describe "run/1" do
    test "requires a module name argument" do
      assert_raise Mix.Error, ~r/Expected module name/, fn ->
        Discover.run([])
      end
    end

    test "discovers a Python module and generates manifest file" do
      output =
        capture_io(fn ->
          Discover.run(["demo"])
        end)

      assert output =~ "Discovering Python library: demo"
      assert output =~ "Manifest written to:"
      assert File.exists?("priv/snakebridge/manifests/_drafts/demo.json")
    end

    test "supports --output option for custom path" do
      capture_io(fn ->
        Discover.run(["demo", "--output", "custom/path/demo.json"])
      end)

      assert File.exists?("custom/path/demo.json")
      File.rm_rf("custom")
    end

    test "supports --depth option for discovery depth" do
      output =
        capture_io(fn ->
          Discover.run(["demo", "--depth", "3"])
        end)

      assert output =~ "Discovery depth: 3"
      assert File.exists?("priv/snakebridge/manifests/_drafts/demo.json")
    end

    test "handles discovery errors gracefully" do
      assert_raise Mix.Error, ~r/Failed to discover/, fn ->
        capture_io(fn ->
          Discover.run(["nonexistent_module"])
        end)
      end
    end

    test "generated manifest file is valid JSON" do
      capture_io(fn ->
        Discover.run(["demo"])
      end)

      manifest_path = "priv/snakebridge/manifests/_drafts/demo.json"
      {:ok, manifest} = SnakeBridge.Manifest.from_file(manifest_path)
      assert manifest.python_module == "demo"
    end

    test "supports --force to overwrite existing files" do
      # Create initial file
      capture_io(fn -> Discover.run(["demo"]) end)

      # Corrupt the file
      File.write!("priv/snakebridge/manifests/_drafts/demo.json", "corrupted content")

      # Try to overwrite without --force (should error)
      assert_raise Mix.Error, ~r/already exists/, fn ->
        capture_io(fn -> Discover.run(["demo"]) end)
      end

      # File should still be corrupted
      assert File.read!("priv/snakebridge/manifests/_drafts/demo.json") == "corrupted content"

      # Overwrite with --force (should succeed and regenerate)
      capture_io(fn -> Discover.run(["demo", "--force"]) end)

      # File should be regenerated, not corrupted
      regenerated = File.read!("priv/snakebridge/manifests/_drafts/demo.json")
      assert regenerated =~ "\"python_module\""
      refute regenerated =~ "# corrupted content"
    end
  end
end
