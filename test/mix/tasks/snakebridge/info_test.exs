defmodule Mix.Tasks.Snakebridge.InfoTest do
  use ExUnit.Case
  import ExUnit.CaptureIO
  alias Mix.Tasks.Snakebridge.Info

  setup do
    # Create a temporary test directory
    base_path = System.tmp_dir!()
    test_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    test_dir = Path.join(base_path, "snakebridge_test_#{test_id}")
    registry_dir = Path.join([test_dir, "priv", "snakebridge"])
    registry_path = Path.join(registry_dir, "registry.json")

    File.mkdir_p!(registry_dir)

    # Create a registry with test data
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
          "files" => ["numpy.ex", "linalg.ex", "fft.ex", "classes/ndarray.ex", "_meta.ex"],
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

    on_exit(fn ->
      File.rm_rf!(test_dir)
    end)

    %{
      test_dir: test_dir,
      registry_path: registry_path,
      registry_data: registry_data
    }
  end

  describe "run/1" do
    test "shows error when no library name provided", %{test_dir: test_dir} do
      in_test_dir(test_dir, fn ->
        assert_raise Mix.Error, ~r/Library name required/, fn ->
          capture_io(fn -> Info.run([]) end)
        end
      end)
    end

    test "shows error when library not found", %{test_dir: test_dir} do
      in_test_dir(test_dir, fn ->
        output =
          capture_io(:stderr, fn ->
            capture_io(fn ->
              assert catch_exit(Info.run(["nonexistent"]))
            end)
          end)

        assert output =~ "Library 'nonexistent' not found"

        # Also check stdout for available libraries list
        stdout =
          capture_io(fn ->
            capture_io(:stderr, fn ->
              catch_exit(Info.run(["nonexistent"]))
            end)
          end)

        assert stdout =~ "Available libraries:"
        assert stdout =~ "json"
        assert stdout =~ "numpy"
      end)
    end

    test "shows detailed information about a library", %{test_dir: test_dir} do
      in_test_dir(test_dir, fn ->
        output =
          capture_io(fn ->
            Info.run(["numpy"])
          end)

        # Header
        assert output =~ "Library: numpy"
        assert output =~ "Python module: numpy (version 1.26.0)"
        assert output =~ "Elixir module: Numpy"
        assert output =~ "Generated: 2024-12-24 14:00:00"

        # Path
        assert output =~ "Path: lib/snakebridge/adapters/numpy/"

        # Stats
        assert output =~ "Statistics:"
        assert output =~ "Functions: 165"
        assert output =~ "Classes: 2"
        assert output =~ "Submodules: 4"

        # Files
        assert output =~ "Files:"
        assert output =~ "numpy.ex"
        assert output =~ "linalg.ex"
        assert output =~ "fft.ex"
        assert output =~ "classes/ndarray.ex"
        assert output =~ "_meta.ex"
      end)
    end

    test "shows information for library with minimal data", %{test_dir: test_dir} do
      in_test_dir(test_dir, fn ->
        output =
          capture_io(fn ->
            Info.run(["json"])
          end)

        assert output =~ "Library: json"
        assert output =~ "Python module: json (version 2.0.9)"
        assert output =~ "Elixir module: Json"
        assert output =~ "Generated: 2024-12-24 15:00:00"
        assert output =~ "Functions: 4"
        assert output =~ "Classes: 3"
        assert output =~ "Submodules: 1"
        assert output =~ "json.ex"
        assert output =~ "_meta.ex"
      end)
    end

    test "handles library with missing stats gracefully", %{
      test_dir: test_dir,
      registry_path: registry_path
    } do
      in_test_dir(test_dir, fn ->
        # Add a library with missing stats
        registry = Jason.decode!(File.read!(registry_path))

        updated_libs =
          Map.put(registry["libraries"], "incomplete", %{
            "python_module" => "incomplete",
            "python_version" => "1.0.0",
            "elixir_module" => "Incomplete",
            "generated_at" => "2024-12-24T16:00:00Z",
            "path" => "lib/snakebridge/adapters/incomplete/",
            "files" => ["incomplete.ex"]
            # Missing stats
          })

        registry = Map.put(registry, "libraries", updated_libs)
        File.write!(registry_path, Jason.encode!(registry, pretty: true))

        output =
          capture_io(fn ->
            Info.run(["incomplete"])
          end)

        assert output =~ "Library: incomplete"
        assert output =~ "Python module: incomplete (version 1.0.0)"
        assert output =~ "Elixir module: Incomplete"
        assert output =~ "Functions: 0"
        assert output =~ "Classes: 0"
        assert output =~ "Submodules: 0"
        assert output =~ "incomplete.ex"
      end)
    end

    test "handles library with missing files list", %{
      test_dir: test_dir,
      registry_path: registry_path
    } do
      in_test_dir(test_dir, fn ->
        # Add a library with missing files
        registry = Jason.decode!(File.read!(registry_path))

        updated_libs =
          Map.put(registry["libraries"], "nofiles", %{
            "python_module" => "nofiles",
            "python_version" => "1.0.0",
            "elixir_module" => "NoFiles",
            "generated_at" => "2024-12-24T16:00:00Z",
            "path" => "lib/snakebridge/adapters/nofiles/",
            "stats" => %{
              "functions" => 5,
              "classes" => 1,
              "submodules" => 1
            }
            # Missing files
          })

        registry = Map.put(registry, "libraries", updated_libs)
        File.write!(registry_path, Jason.encode!(registry, pretty: true))

        output =
          capture_io(fn ->
            Info.run(["nofiles"])
          end)

        assert output =~ "Library: nofiles"
        assert output =~ "Functions: 5"
        assert output =~ "Classes: 1"
        assert output =~ "Files:"
        assert output =~ "(none)"
      end)
    end

    test "shows quick start example", %{test_dir: test_dir} do
      in_test_dir(test_dir, fn ->
        output =
          capture_io(fn ->
            Info.run(["numpy"])
          end)

        assert output =~ "Quick start:"
        assert output =~ "alias Numpy"
        assert output =~ "Numpy"
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
