defmodule Mix.Tasks.Snakebridge.RemoveTest do
  use ExUnit.Case
  import ExUnit.CaptureIO
  alias Mix.Tasks.Snakebridge.Remove

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
        }
      }
    }

    File.write!(registry_path, Jason.encode!(registry_data, pretty: true))

    # Create mock adapter directories
    numpy_dir = Path.join(adapters_dir, "numpy")
    json_dir = Path.join(adapters_dir, "json")
    File.mkdir_p!(numpy_dir)
    File.mkdir_p!(json_dir)

    File.write!(Path.join(numpy_dir, "numpy.ex"), "# Numpy adapter")
    File.write!(Path.join(numpy_dir, "linalg.ex"), "# Numpy Linalg")
    File.write!(Path.join(numpy_dir, "_meta.ex"), "# Numpy Meta")
    File.write!(Path.join(json_dir, "json.ex"), "# JSON adapter")
    File.write!(Path.join(json_dir, "_meta.ex"), "# JSON Meta")

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
    test "shows error when no library name provided", %{test_dir: test_dir} do
      in_test_dir(test_dir, fn ->
        assert_raise Mix.Error, ~r/Library name required/, fn ->
          capture_io(fn -> Remove.run([]) end)
        end
      end)
    end

    test "shows error when library not found in registry", %{test_dir: test_dir} do
      in_test_dir(test_dir, fn ->
        output =
          capture_io(:stderr, fn ->
            capture_io(fn ->
              assert catch_exit(Remove.run(["nonexistent"]))
            end)
          end)

        assert output =~ "Library 'nonexistent' not found"
      end)
    end

    test "removes library adapter and updates registry", %{
      test_dir: test_dir,
      adapters_dir: adapters_dir,
      registry_path: registry_path
    } do
      in_test_dir(test_dir, fn ->
        numpy_dir = Path.join(adapters_dir, "numpy")
        assert File.dir?(numpy_dir)

        output =
          capture_io(fn ->
            Remove.run(["numpy"])
          end)

        assert output =~ "Removing numpy..."
        assert output =~ "Deleted: lib/snakebridge/adapters/numpy/"
        assert output =~ "Updated: priv/snakebridge/registry.json"
        assert output =~ "Done. Run `mix snakebridge.gen numpy` to regenerate."

        # Verify directory was removed
        refute File.dir?(numpy_dir)

        # Verify registry was updated
        registry = Jason.decode!(File.read!(registry_path))
        refute Map.has_key?(registry["libraries"], "numpy")
        assert Map.has_key?(registry["libraries"], "json")
      end)
    end

    test "shows error when adapter directory doesn't exist", %{
      test_dir: test_dir,
      adapters_dir: adapters_dir,
      registry_path: registry_path
    } do
      in_test_dir(test_dir, fn ->
        # Remove the numpy directory but keep it in registry
        numpy_dir = Path.join(adapters_dir, "numpy")
        File.rm_rf!(numpy_dir)

        output =
          capture_io(fn ->
            Remove.run(["numpy"])
          end)

        assert output =~ "Warning: Adapter directory does not exist"
        assert output =~ "Updated: priv/snakebridge/registry.json"

        # Registry should still be updated
        registry = Jason.decode!(File.read!(registry_path))
        refute Map.has_key?(registry["libraries"], "numpy")
      end)
    end

    test "handles absolute and relative paths in registry", %{test_dir: test_dir} do
      in_test_dir(test_dir, fn ->
        output =
          capture_io(fn ->
            Remove.run(["json"])
          end)

        assert output =~ "Removing json..."
        assert output =~ "Done."
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
