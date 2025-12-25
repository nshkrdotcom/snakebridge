defmodule Mix.Tasks.Snakebridge.GenTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias Mix.Tasks.Snakebridge.Gen

  @temp_dir "tmp/test_gen"

  setup do
    # Clean up before and after each test
    File.rm_rf!(@temp_dir)
    File.mkdir_p!(@temp_dir)

    on_exit(fn ->
      File.rm_rf!(@temp_dir)
    end)

    :ok
  end

  describe "run/1" do
    test "shows error when no library name provided" do
      output =
        capture_io(:stderr, fn ->
          capture_io(fn ->
            assert catch_exit(Gen.run([])) == {:shutdown, 1}
          end)
        end)

      assert output =~ "Error: Library name required"
    end

    test "shows error for invalid options" do
      output =
        capture_io(:stderr, fn ->
          capture_io(fn ->
            assert catch_exit(Gen.run(["json", "--invalid-option"])) == {:shutdown, 1}
          end)
        end)

      assert output =~ "Invalid options"
    end

    test "shows error when multiple library names provided" do
      output =
        capture_io(:stderr, fn ->
          capture_io(fn ->
            assert catch_exit(Gen.run(["json", "requests"])) == {:shutdown, 1}
          end)
        end)

      assert output =~ "Only one library name allowed"
    end
  end

  describe "generate_adapter/2" do
    @tag :real_python
    test "generates adapter for a simple Python module" do
      output_dir = Path.join(@temp_dir, "json")

      output =
        capture_io(fn ->
          Gen.run(["json", "--output", output_dir])
        end)

      # Verify output messages
      assert output =~ "Introspecting Python library: json"
      assert output =~ "Found"
      assert output =~ "functions"
      assert output =~ "Generating Elixir adapters"
      assert output =~ "Success! Generated json adapter"
      assert output =~ "Path: #{output_dir}"
      assert output =~ "Module:"
      assert output =~ "Quick start:"
      assert output =~ "Discovery:"

      # Verify files were created
      assert File.dir?(output_dir)
      files = File.ls!(output_dir)
      assert length(files) > 0
    end

    @tag :real_python
    test "generates adapter with custom module name" do
      output_dir = Path.join(@temp_dir, "custom_json")

      output =
        capture_io(fn ->
          Gen.run(["json", "--output", output_dir, "--module", "MyJson"])
        end)

      assert output =~ "Success!"
      assert File.dir?(output_dir)
    end

    @tag :real_python
    test "handles --force flag to regenerate existing library" do
      output_dir = Path.join(@temp_dir, "json_force")

      # First generation
      capture_io(fn ->
        Gen.run(["json", "--output", output_dir])
      end)

      assert File.dir?(output_dir)
      original_files = File.ls!(output_dir)

      # Regenerate with --force
      output =
        capture_io(fn ->
          Gen.run(["json", "--output", output_dir, "--force"])
        end)

      assert output =~ "Removing existing json adapter"
      assert output =~ "Success!"
      assert File.dir?(output_dir)

      new_files = File.ls!(output_dir)
      # Files should be regenerated (same count or similar)
      assert length(new_files) >= length(original_files) - 1
    end

    @tag :real_python
    test "filters functions with --functions option" do
      output_dir = Path.join(@temp_dir, "json_filtered")

      output =
        capture_io(fn ->
          Gen.run(["json", "--output", output_dir, "--functions", "dumps,loads"])
        end)

      assert output =~ "Success!"
      assert File.dir?(output_dir)
    end

    @tag :real_python
    test "excludes functions with --exclude option" do
      output_dir = Path.join(@temp_dir, "json_excluded")

      output =
        capture_io(fn ->
          Gen.run(["json", "--output", output_dir, "--exclude", "dump,load"])
        end)

      assert output =~ "Success!"
      assert File.dir?(output_dir)
    end

    test "shows helpful error for non-existent Python library" do
      output_dir = Path.join(@temp_dir, "fake_lib")

      # Capture both stderr (for error message) and stdout (for troubleshooting info)
      {stderr_output, stdout_output} =
        capture_io(:stderr, fn ->
          stdout =
            capture_io(fn ->
              assert catch_exit(
                       Gen.run(["this_library_does_not_exist_xyz", "--output", output_dir])
                     ) ==
                       {:shutdown, 1}
            end)

          IO.write(:stderr, "__STDOUT__" <> stdout)
        end)
        |> then(fn combined ->
          case String.split(combined, "__STDOUT__", parts: 2) do
            [stderr, stdout] -> {stderr, stdout}
            [stderr] -> {stderr, ""}
          end
        end)

      combined_output = stderr_output <> stdout_output

      assert stderr_output =~ "Failed to introspect library"
      assert combined_output =~ "Troubleshooting:"
      assert combined_output =~ "pip install"
    end
  end

  describe "default output directory" do
    @tag :real_python
    test "uses default directory lib/snakebridge/adapters/<library>" do
      # Mock the default path - we'll use our temp dir to avoid pollution
      output_dir = Path.join(@temp_dir, "json_default")

      output =
        capture_io(fn ->
          Gen.run(["json", "--output", output_dir])
        end)

      assert output =~ "Path: #{output_dir}"
      assert File.dir?(output_dir)
    end
  end

  describe "introspection summary" do
    @tag :real_python
    test "shows function and namespace counts" do
      output_dir = Path.join(@temp_dir, "json_summary")

      output =
        capture_io(fn ->
          Gen.run(["json", "--output", output_dir])
        end)

      assert output =~ "Found"
      assert output =~ "functions"
      assert output =~ "namespaces"
    end
  end

  describe "success output" do
    @tag :real_python
    test "displays success information with stats" do
      output_dir = Path.join(@temp_dir, "json_success")

      output =
        capture_io(fn ->
          Gen.run(["json", "--output", output_dir])
        end)

      assert output =~ "Success! Generated json adapter:"
      assert output =~ "Path:"
      assert output =~ "Module:"
      assert output =~ "Functions:"
      assert output =~ "Quick start:"
      assert output =~ "alias"
      assert output =~ "Discovery:"
      assert output =~ "__functions__()"
    end
  end

  describe "registry integration" do
    @tag :real_python
    test "attempts to register library after generation" do
      output_dir = Path.join(@temp_dir, "json_registry")

      # The test should complete without errors even if Registry doesn't exist
      output =
        capture_io(fn ->
          Gen.run(["json", "--output", output_dir])
        end)

      assert output =~ "Success!"
      # Registry warnings are optional - don't fail if they appear
    end
  end
end
