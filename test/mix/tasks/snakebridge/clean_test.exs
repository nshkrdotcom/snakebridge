defmodule Mix.Tasks.Snakebridge.CleanTest do
  use ExUnit.Case
  import ExUnit.CaptureIO
  alias Mix.Tasks.Snakebridge.Clean

  setup do
    # Create a temporary test directory
    base_path = System.tmp_dir!()
    test_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    test_dir = Path.join(base_path, "snakebridge_test_#{test_id}")
    adapters_dir = Path.join([test_dir, "lib", "snakebridge", "adapters"])
    registry_dir = Path.join([test_dir, "priv", "snakebridge"])
    registry_path = Path.join(registry_dir, "registry.json")

    File.mkdir_p!(adapters_dir)
    File.mkdir_p!(registry_dir)

    # Create a mock registry file
    registry_data = %{
      "version" => "2.1",
      "generated_at" => "2024-12-24T15:30:00Z",
      "libraries" => %{
        "numpy" => %{
          "python_module" => "numpy",
          "python_version" => "1.26.0",
          "elixir_module" => "Numpy",
          "generated_at" => "2024-12-24T14:00:00Z",
          "path" => "lib/snakebridge/adapters/numpy/",
          "files" => ["numpy.ex", "linalg.ex", "_meta.ex"],
          "stats" => %{
            "functions" => 165,
            "classes" => 2,
            "submodules" => 4
          }
        },
        "json" => %{
          "python_module" => "json",
          "python_version" => "2.0.9",
          "elixir_module" => "Json",
          "generated_at" => "2024-12-24T15:00:00Z",
          "path" => "lib/snakebridge/adapters/json/",
          "files" => ["json.ex", "_meta.ex"],
          "stats" => %{
            "functions" => 4,
            "classes" => 3,
            "submodules" => 1
          }
        },
        "requests" => %{
          "python_module" => "requests",
          "python_version" => "2.31.0",
          "elixir_module" => "Requests",
          "generated_at" => "2024-12-24T15:00:00Z",
          "path" => "lib/snakebridge/adapters/requests/",
          "files" => ["requests.ex", "_meta.ex"],
          "stats" => %{
            "functions" => 12,
            "classes" => 1,
            "submodules" => 1
          }
        }
      }
    }

    File.write!(registry_path, Jason.encode!(registry_data, pretty: true))

    # Create mock adapter directories
    numpy_dir = Path.join(adapters_dir, "numpy")
    json_dir = Path.join(adapters_dir, "json")
    requests_dir = Path.join(adapters_dir, "requests")
    File.mkdir_p!(numpy_dir)
    File.mkdir_p!(json_dir)
    File.mkdir_p!(requests_dir)

    File.write!(Path.join(numpy_dir, "numpy.ex"), "# Numpy adapter")
    File.write!(Path.join(numpy_dir, "linalg.ex"), "# Numpy Linalg")
    File.write!(Path.join(numpy_dir, "_meta.ex"), "# Numpy Meta")
    File.write!(Path.join(json_dir, "json.ex"), "# JSON adapter")
    File.write!(Path.join(json_dir, "_meta.ex"), "# JSON Meta")
    File.write!(Path.join(requests_dir, "requests.ex"), "# Requests adapter")
    File.write!(Path.join(requests_dir, "_meta.ex"), "# Requests Meta")

    on_exit(fn ->
      File.rm_rf!(test_dir)
    end)

    %{
      test_dir: test_dir,
      adapters_dir: adapters_dir,
      registry_path: registry_path,
      registry_data: registry_data
    }
  end

  describe "run/1" do
    test "shows message when no adapters exist", %{test_dir: test_dir} do
      in_test_dir(test_dir, fn ->
        # Clear the registry
        registry_path = "priv/snakebridge/registry.json"

        empty_registry = %{
          "version" => "2.1",
          "generated_at" => "2024-12-24T15:30:00Z",
          "libraries" => %{}
        }

        File.mkdir_p!(Path.dirname(registry_path))
        File.write!(registry_path, Jason.encode!(empty_registry, pretty: true))

        output =
          capture_io(fn ->
            assert catch_exit(Clean.run([]))
          end)

        assert output =~ "No generated adapters to clean."
      end)
    end

    test "shows confirmation prompt with library list", %{test_dir: test_dir} do
      in_test_dir(test_dir, fn ->
        output =
          capture_io([input: "n\n"], fn ->
            assert catch_exit(Clean.run([]))
          end)

        assert output =~ "This will remove all generated adapters:"
        assert output =~ "numpy (165 functions)"
        assert output =~ "json (4 functions)"
        assert output =~ "requests (12 functions)"
        assert output =~ "Continue? [y/N]"
      end)
    end

    test "cancels when user declines confirmation", %{test_dir: test_dir} do
      in_test_dir(test_dir, fn ->
        output =
          capture_io([input: "n\n"], fn ->
            assert catch_exit(Clean.run([]))
          end)

        assert output =~ "Cancelled."
      end)
    end

    test "removes all adapters when user confirms", %{
      test_dir: test_dir,
      adapters_dir: adapters_dir,
      registry_path: registry_path
    } do
      in_test_dir(test_dir, fn ->
        # Verify directories exist
        assert File.dir?(Path.join(adapters_dir, "numpy"))
        assert File.dir?(Path.join(adapters_dir, "json"))
        assert File.dir?(Path.join(adapters_dir, "requests"))

        output =
          capture_io([input: "y\n"], fn ->
            Clean.run([])
          end)

        assert output =~ "Removing numpy..."
        assert output =~ "Removing json..."
        assert output =~ "Removing requests..."
        assert output =~ "Removed 3 libraries."
        assert output =~ "Registry cleared."

        # Verify directories were removed
        refute File.dir?(Path.join(adapters_dir, "numpy"))
        refute File.dir?(Path.join(adapters_dir, "json"))
        refute File.dir?(Path.join(adapters_dir, "requests"))

        # Verify registry was cleared
        registry = Jason.decode!(File.read!(registry_path))
        assert registry["libraries"] == %{}
      end)
    end

    test "skips confirmation with --yes flag", %{
      test_dir: test_dir,
      adapters_dir: adapters_dir
    } do
      in_test_dir(test_dir, fn ->
        output =
          capture_io(fn ->
            Clean.run(["--yes"])
          end)

        assert output =~ "Removing numpy..."
        assert output =~ "Removing json..."
        assert output =~ "Removing requests..."
        assert output =~ "Removed 3 libraries."

        # Verify directories were removed
        refute File.dir?(Path.join(adapters_dir, "numpy"))
        refute File.dir?(Path.join(adapters_dir, "json"))
        refute File.dir?(Path.join(adapters_dir, "requests"))
      end)
    end

    test "handles missing adapter directories gracefully", %{
      test_dir: test_dir,
      adapters_dir: adapters_dir,
      registry_path: registry_path
    } do
      in_test_dir(test_dir, fn ->
        # Remove one directory but keep it in registry
        File.rm_rf!(Path.join(adapters_dir, "json"))

        output =
          capture_io([input: "y\n"], fn ->
            Clean.run([])
          end)

        assert output =~ "Removing numpy..."
        assert output =~ "Removing json..."
        assert output =~ "Removing requests..."
        assert output =~ "Removed 3 libraries."

        # Registry should still be cleared
        registry = Jason.decode!(File.read!(registry_path))
        assert registry["libraries"] == %{}
      end)
    end
  end

  # Helper to run code in test directory context
  defp in_test_dir(dir, fun) do
    original_dir = File.cwd!()
    File.cd!(dir)

    try do
      fun.()
    after
      File.cd!(original_dir)
    end
  end
end
