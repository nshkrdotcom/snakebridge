defmodule SnakeBridge.RegistryTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.Registry

  import SnakeBridge.TestHelpers

  @moduletag :tmp_dir

  setup do
    # Use a temporary registry file for testing
    registry_path = tmp_path("_registry.json")

    # Store original path and set test path
    original_path = Application.get_env(:snakebridge, :registry_path)
    Application.put_env(:snakebridge, :registry_path, registry_path)

    # Ensure clean state
    Registry.clear()

    on_exit(fn ->
      # Restore original path
      if original_path do
        Application.put_env(:snakebridge, :registry_path, original_path)
      else
        Application.delete_env(:snakebridge, :registry_path)
      end

      # Clean up test file
      File.rm(registry_path)
    end)

    {:ok, registry_path: registry_path}
  end

  describe "list_libraries/0" do
    test "returns empty list when no libraries registered" do
      assert Registry.list_libraries() == []
    end

    test "returns list of library names after registration" do
      entry1 = build_entry("numpy")
      entry2 = build_entry("json")

      Registry.register("numpy", entry1)
      Registry.register("json", entry2)

      libraries = Registry.list_libraries()
      assert length(libraries) == 2
      assert "numpy" in libraries
      assert "json" in libraries
    end

    test "returns sorted list of libraries" do
      Registry.register("sympy", build_entry("sympy"))
      Registry.register("numpy", build_entry("numpy"))
      Registry.register("json", build_entry("json"))

      assert Registry.list_libraries() == ["json", "numpy", "sympy"]
    end
  end

  describe "get/1" do
    test "returns nil when library not registered" do
      assert Registry.get("nonexistent") == nil
    end

    test "returns library info when registered" do
      entry = build_entry("numpy")
      Registry.register("numpy", entry)

      result = Registry.get("numpy")
      assert result != nil
      assert result.python_module == "numpy"
      assert result.elixir_module == "Numpy"
    end

    test "returns complete entry with all fields" do
      entry = %{
        python_module: "numpy",
        python_version: "1.26.0",
        elixir_module: "Numpy",
        generated_at: ~U[2024-12-24 14:00:00Z],
        path: "lib/snakebridge/adapters/numpy/",
        files: ["numpy.ex", "linalg.ex", "_meta.ex"],
        stats: %{functions: 165, classes: 2, submodules: 4}
      }

      Registry.register("numpy", entry)

      result = Registry.get("numpy")
      assert result.python_module == "numpy"
      assert result.python_version == "1.26.0"
      assert result.elixir_module == "Numpy"
      assert result.generated_at == ~U[2024-12-24 14:00:00Z]
      assert result.path == "lib/snakebridge/adapters/numpy/"
      assert result.files == ["numpy.ex", "linalg.ex", "_meta.ex"]
      assert result.stats.functions == 165
      assert result.stats.classes == 2
      assert result.stats.submodules == 4
    end
  end

  describe "generated?/1" do
    test "returns false when library not registered" do
      assert Registry.generated?("numpy") == false
    end

    test "returns true when library is registered" do
      Registry.register("numpy", build_entry("numpy"))
      assert Registry.generated?("numpy") == true
    end

    test "returns false after library is unregistered" do
      Registry.register("numpy", build_entry("numpy"))
      assert Registry.generated?("numpy") == true

      Registry.unregister("numpy")
      assert Registry.generated?("numpy") == false
    end
  end

  describe "register/2" do
    test "adds library to registry" do
      entry = build_entry("numpy")
      assert Registry.register("numpy", entry) == :ok

      assert Registry.generated?("numpy") == true
      assert Registry.get("numpy") != nil
    end

    test "updates existing library entry" do
      entry1 = build_entry("numpy", python_version: "1.25.0")
      entry2 = build_entry("numpy", python_version: "1.26.0")

      Registry.register("numpy", entry1)
      assert Registry.get("numpy").python_version == "1.25.0"

      Registry.register("numpy", entry2)
      assert Registry.get("numpy").python_version == "1.26.0"
    end

    test "returns error for invalid entry" do
      # Missing required fields
      invalid_entry = %{python_module: "numpy"}

      assert {:error, reason} = Registry.register("numpy", invalid_entry)
      assert is_binary(reason)
    end

    test "validates entry structure" do
      valid_entry = %{
        python_module: "numpy",
        python_version: "1.26.0",
        elixir_module: "Numpy",
        generated_at: ~U[2024-12-24 14:00:00Z],
        path: "lib/snakebridge/adapters/numpy/",
        files: ["numpy.ex"],
        stats: %{functions: 10, classes: 0, submodules: 1}
      }

      assert Registry.register("numpy", valid_entry) == :ok
    end
  end

  describe "unregister/1" do
    test "removes library from registry" do
      Registry.register("numpy", build_entry("numpy"))
      assert Registry.generated?("numpy") == true

      assert Registry.unregister("numpy") == :ok
      assert Registry.generated?("numpy") == false
    end

    test "returns ok even if library not registered" do
      assert Registry.unregister("nonexistent") == :ok
    end

    test "does not affect other libraries" do
      Registry.register("numpy", build_entry("numpy"))
      Registry.register("json", build_entry("json"))

      Registry.unregister("numpy")

      assert Registry.generated?("numpy") == false
      assert Registry.generated?("json") == true
    end
  end

  describe "clear/0" do
    test "removes all libraries from registry" do
      Registry.register("numpy", build_entry("numpy"))
      Registry.register("json", build_entry("json"))
      Registry.register("sympy", build_entry("sympy"))

      assert length(Registry.list_libraries()) == 3

      Registry.clear()

      assert Registry.list_libraries() == []
    end

    test "clears empty registry without error" do
      assert Registry.clear() == :ok
      assert Registry.list_libraries() == []
    end
  end

  describe "save/0" do
    test "persists registry to JSON file", %{registry_path: path} do
      Registry.register("numpy", build_entry("numpy"))
      Registry.register("json", build_entry("json"))

      assert Registry.save() == :ok
      assert File.exists?(path)

      # Verify JSON structure
      {:ok, content} = File.read(path)
      {:ok, data} = Jason.decode(content)

      assert data["version"] == "2.1"
      assert is_binary(data["generated_at"])
      assert is_map(data["libraries"])
      assert Map.has_key?(data["libraries"], "numpy")
      assert Map.has_key?(data["libraries"], "json")
    end

    test "creates parent directory if needed" do
      nested_path = tmp_path("/nested/deep/registry.json")
      Application.put_env(:snakebridge, :registry_path, nested_path)

      Registry.register("test", build_entry("test"))
      assert Registry.save() == :ok

      assert File.exists?(nested_path)

      # Cleanup
      File.rm_rf!(Path.dirname(nested_path))
    end

    test "saves empty registry" do
      Registry.clear()
      assert Registry.save() == :ok

      {:ok, content} = File.read(Application.get_env(:snakebridge, :registry_path))
      {:ok, data} = Jason.decode(content)

      assert data["libraries"] == %{}
    end

    test "preserves DateTime in ISO8601 format", %{registry_path: path} do
      timestamp = ~U[2024-12-24 14:30:00Z]
      entry = build_entry("numpy", generated_at: timestamp)

      Registry.register("numpy", entry)
      Registry.save()

      {:ok, content} = File.read(path)
      {:ok, data} = Jason.decode(content)

      assert data["libraries"]["numpy"]["generated_at"] == "2024-12-24T14:30:00Z"
    end
  end

  describe "load/0" do
    test "loads registry from JSON file", %{registry_path: path} do
      # Create a test registry file
      registry_data = %{
        "version" => "2.1",
        "generated_at" => "2024-12-24T15:00:00Z",
        "libraries" => %{
          "numpy" => %{
            "python_module" => "numpy",
            "python_version" => "1.26.0",
            "elixir_module" => "Numpy",
            "generated_at" => "2024-12-24T14:00:00Z",
            "path" => "lib/snakebridge/adapters/numpy/",
            "files" => ["numpy.ex", "linalg.ex"],
            "stats" => %{
              "functions" => 165,
              "classes" => 2,
              "submodules" => 4
            }
          }
        }
      }

      File.write!(path, Jason.encode!(registry_data))

      assert Registry.load() == :ok

      assert Registry.generated?("numpy") == true
      result = Registry.get("numpy")
      assert result.python_module == "numpy"
      assert result.python_version == "1.26.0"
      assert result.stats.functions == 165
    end

    test "handles missing file gracefully" do
      # Delete the file if it exists
      path = Application.get_env(:snakebridge, :registry_path)
      File.rm(path)

      assert Registry.load() == :ok
      assert Registry.list_libraries() == []
    end

    test "handles corrupted JSON file" do
      path = Application.get_env(:snakebridge, :registry_path)
      File.write!(path, "invalid json {{{")

      # Should return error but not crash
      assert {:error, _reason} = Registry.load()
    end

    test "handles invalid registry structure" do
      path = Application.get_env(:snakebridge, :registry_path)

      # Valid JSON but wrong structure
      File.write!(path, Jason.encode!(%{"invalid" => "structure"}))

      assert {:error, _reason} = Registry.load()
    end

    test "converts DateTime strings to DateTime structs" do
      path = Application.get_env(:snakebridge, :registry_path)

      registry_data = %{
        "version" => "2.1",
        "generated_at" => "2024-12-24T15:00:00Z",
        "libraries" => %{
          "numpy" => %{
            "python_module" => "numpy",
            "python_version" => "1.26.0",
            "elixir_module" => "Numpy",
            "generated_at" => "2024-12-24T14:00:00Z",
            "path" => "lib/snakebridge/adapters/numpy/",
            "files" => ["numpy.ex"],
            "stats" => %{"functions" => 10, "classes" => 0, "submodules" => 1}
          }
        }
      }

      File.write!(path, Jason.encode!(registry_data))
      Registry.load()

      result = Registry.get("numpy")
      assert %DateTime{} = result.generated_at
      assert DateTime.to_iso8601(result.generated_at) == "2024-12-24T14:00:00Z"
    end
  end

  describe "persistence" do
    test "save and load round-trip preserves data", %{registry_path: _path} do
      entry1 =
        build_entry("numpy",
          python_version: "1.26.0",
          files: ["numpy.ex", "linalg.ex", "fft.ex"],
          stats: %{functions: 165, classes: 2, submodules: 4}
        )

      entry2 =
        build_entry("json",
          python_version: "2.0.9",
          files: ["json.ex", "_meta.ex"],
          stats: %{functions: 4, classes: 3, submodules: 1}
        )

      Registry.register("numpy", entry1)
      Registry.register("json", entry2)

      assert Registry.save() == :ok

      # Clear in-memory registry
      Registry.clear()
      assert Registry.list_libraries() == []

      # Load from file
      assert Registry.load() == :ok

      # Verify data is restored
      assert length(Registry.list_libraries()) == 2
      assert Registry.generated?("numpy") == true
      assert Registry.generated?("json") == true

      numpy_result = Registry.get("numpy")
      assert numpy_result.python_version == "1.26.0"
      assert numpy_result.stats.functions == 165

      json_result = Registry.get("json")
      assert json_result.python_version == "2.0.9"
      assert json_result.stats.classes == 3
    end

    test "auto-saves after register when configured" do
      # This test verifies that registry can be configured to auto-save
      # For now, we test manual save/load cycle
      Registry.register("test", build_entry("test"))
      Registry.save()

      Registry.clear()
      Registry.load()

      assert Registry.generated?("test") == true
    end
  end

  describe "concurrency" do
    test "handles concurrent registrations" do
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            lib_name = "lib#{i}"
            entry = build_entry(lib_name)
            Registry.register(lib_name, entry)
          end)
        end

      Task.await_many(tasks)

      assert length(Registry.list_libraries()) == 10
    end

    test "handles concurrent reads" do
      Registry.register("numpy", build_entry("numpy"))

      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            Registry.get("numpy")
          end)
        end

      results = Task.await_many(tasks)

      assert Enum.all?(results, fn result ->
               result != nil && result.python_module == "numpy"
             end)
    end
  end

  describe "edge cases" do
    test "handles library name with special characters" do
      # Library names might have dots or underscores
      entry = build_entry("urllib.parse", python_module: "urllib.parse")

      assert Registry.register("urllib.parse", entry) == :ok
      assert Registry.generated?("urllib.parse") == true
    end

    test "handles empty files list" do
      entry = build_entry("test", files: [])

      assert Registry.register("test", entry) == :ok
      result = Registry.get("test")
      assert result.files == []
    end

    test "handles zero stats" do
      entry = build_entry("test", stats: %{functions: 0, classes: 0, submodules: 0})

      assert Registry.register("test", entry) == :ok
      result = Registry.get("test")
      assert result.stats.functions == 0
    end

    test "handles very long file lists" do
      many_files = for i <- 1..100, do: "file#{i}.ex"
      entry = build_entry("large_lib", files: many_files)

      assert Registry.register("large_lib", entry) == :ok
      result = Registry.get("large_lib")
      assert length(result.files) == 100
    end
  end

  # Helper function to build a registry entry
  defp build_entry(name, opts \\ []) do
    %{
      python_module: Keyword.get(opts, :python_module, name),
      python_version: Keyword.get(opts, :python_version, "1.0.0"),
      elixir_module: Keyword.get(opts, :elixir_module, Macro.camelize(name)),
      generated_at: Keyword.get(opts, :generated_at, DateTime.utc_now()),
      path: Keyword.get(opts, :path, "lib/snakebridge/adapters/#{name}/"),
      files: Keyword.get(opts, :files, ["#{name}.ex", "_meta.ex"]),
      stats: Keyword.get(opts, :stats, %{functions: 10, classes: 0, submodules: 1})
    }
  end
end
