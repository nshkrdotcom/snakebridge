defmodule Mix.Tasks.Snakebridge.ValidateTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.Snakebridge.Validate

  @moduletag :mix_task

  setup do
    # Create test config directory
    File.mkdir_p!("config/snakebridge")

    # Clean up after tests
    on_exit(fn ->
      File.rm_rf("config/snakebridge")
    end)

    :ok
  end

  describe "run/1" do
    test "validates all configs in config/snakebridge/" do
      # Create valid config
      write_valid_config("config/snakebridge/test.exs")

      output =
        capture_io(fn ->
          Validate.run([])
        end)

      assert output =~ "Validating configs"
      assert output =~ "test.exs"
      assert output =~ "✓"
      assert output =~ "1 config(s) validated"
    end

    test "reports invalid configs with error messages" do
      # Create invalid config (missing python_module)
      File.write!("config/snakebridge/invalid.exs", """
      %SnakeBridge.Config{
        version: "1.0.0"
      }
      """)

      # Should raise Mix.Error with message about validation failure
      assert_raise Mix.Error, ~r/failed validation/, fn ->
        capture_io(fn ->
          Validate.run([])
        end)
      end

      # Verify the invalid file was created
      assert File.exists?("config/snakebridge/invalid.exs")
    end

    test "validates specific config when path provided" do
      write_valid_config("config/snakebridge/test.exs")

      output =
        capture_io(fn ->
          Validate.run(["config/snakebridge/test.exs"])
        end)

      assert output =~ "test.exs"
      assert output =~ "✓"
    end

    test "reports when no configs found" do
      output =
        capture_io(fn ->
          Validate.run([])
        end)

      assert output =~ "No config files found"
    end

    test "validates multiple configs and reports summary" do
      write_valid_config("config/snakebridge/demo.exs")
      write_valid_config("config/snakebridge/langchain.exs")

      output =
        capture_io(fn ->
          Validate.run([])
        end)

      assert output =~ "demo.exs"
      assert output =~ "langchain.exs"
      assert output =~ "2 config(s) validated"
    end
  end

  defp write_valid_config(path) do
    File.write!(path, """
    %SnakeBridge.Config{
      python_module: "test_module",
      version: "1.0.0"
    }
    """)
  end
end
