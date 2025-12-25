defmodule Mix.Tasks.Snakebridge.ListTest do
  use ExUnit.Case
  import ExUnit.CaptureIO
  alias Mix.Tasks.Snakebridge.List

  setup do
    # Create a temporary test directory
    base_path = System.tmp_dir!()
    test_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    test_dir = Path.join(base_path, "snakebridge_test_#{test_id}")
    registry_dir = Path.join([test_dir, "priv", "snakebridge"])
    registry_path = Path.join(registry_dir, "registry.json")

    File.mkdir_p!(registry_dir)

    on_exit(fn ->
      File.rm_rf!(test_dir)
    end)

    %{
      test_dir: test_dir,
      registry_dir: registry_dir,
      registry_path: registry_path
    }
  end

  describe "run/1" do
    test "shows message when no adapters exist", %{test_dir: test_dir} do
      in_test_dir(test_dir, fn ->
        # Create empty registry
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
            assert catch_exit(List.run([]))
          end)

        assert output =~ "No generated adapters found."
        assert output =~ "Run `mix snakebridge.gen <library>` to generate an adapter."
      end)
    end

    test "shows message when registry doesn't exist", %{test_dir: test_dir} do
      in_test_dir(test_dir, fn ->
        output =
          capture_io(fn ->
            assert catch_exit(List.run([]))
          end)

        assert output =~ "No generated adapters found."
      end)
    end

    test "lists all generated libraries in a table", %{
      test_dir: test_dir,
      registry_path: registry_path
    } do
      in_test_dir(test_dir, fn ->
        # Create registry with multiple libraries
        registry = %{
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

        File.write!(registry_path, Jason.encode!(registry, pretty: true))

        output =
          capture_io(fn ->
            List.run([])
          end)

        assert output =~ "Generated libraries:"
        assert output =~ "Library"
        assert output =~ "Functions"
        assert output =~ "Classes"
        assert output =~ "Path"

        # Check library entries
        assert output =~ "json"
        assert output =~ "4"
        assert output =~ "3"
        assert output =~ "lib/snakebridge/adapters/json/"

        assert output =~ "numpy"
        assert output =~ "165"
        assert output =~ "2"
        assert output =~ "lib/snakebridge/adapters/numpy/"

        assert output =~ "requests"
        assert output =~ "12"
        assert output =~ "1"
        assert output =~ "lib/snakebridge/adapters/requests/"

        # Check footer
        assert output =~ "Total: 3 libraries"
      end)
    end

    test "handles libraries with missing stats", %{
      test_dir: test_dir,
      registry_path: registry_path
    } do
      in_test_dir(test_dir, fn ->
        # Create registry with library missing stats
        registry = %{
          "version" => "2.1",
          "generated_at" => "2024-12-24T15:30:00Z",
          "libraries" => %{
            "incomplete" => %{
              "python_module" => "incomplete",
              "python_version" => "1.0.0",
              "elixir_module" => "Incomplete",
              "generated_at" => "2024-12-24T15:00:00Z",
              "path" => "lib/snakebridge/adapters/incomplete/",
              "files" => ["incomplete.ex"]
              # Missing stats
            }
          }
        }

        File.write!(registry_path, Jason.encode!(registry, pretty: true))

        output =
          capture_io(fn ->
            List.run([])
          end)

        assert output =~ "incomplete"
        # Should show 0 for missing stats
        assert output =~ "0"
        assert output =~ "lib/snakebridge/adapters/incomplete/"
      end)
    end

    test "shows libraries in alphabetical order", %{
      test_dir: test_dir,
      registry_path: registry_path
    } do
      in_test_dir(test_dir, fn ->
        registry = %{
          "version" => "2.1",
          "generated_at" => "2024-12-24T15:30:00Z",
          "libraries" => %{
            "zlib" => %{
              "path" => "lib/snakebridge/adapters/zlib/",
              "stats" => %{"functions" => 5, "classes" => 0, "submodules" => 1}
            },
            "abc" => %{
              "path" => "lib/snakebridge/adapters/abc/",
              "stats" => %{"functions" => 3, "classes" => 1, "submodules" => 1}
            },
            "math" => %{
              "path" => "lib/snakebridge/adapters/math/",
              "stats" => %{"functions" => 10, "classes" => 0, "submodules" => 1}
            }
          }
        }

        File.write!(registry_path, Jason.encode!(registry, pretty: true))

        output =
          capture_io(fn ->
            List.run([])
          end)

        # Extract positions of library names in output
        abc_pos = :binary.match(output, "abc") |> elem(0)
        math_pos = :binary.match(output, "math") |> elem(0)
        zlib_pos = :binary.match(output, "zlib") |> elem(0)

        # Verify alphabetical order
        assert abc_pos < math_pos
        assert math_pos < zlib_pos
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
