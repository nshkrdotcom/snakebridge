defmodule SnakeBridge.RegistryFileTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.Registry

  @registry_path Path.join([File.cwd!(), "priv", "snakebridge", "registry.json"])

  setup do
    # Backup existing registry if present
    backup_path = @registry_path <> ".backup"
    had_file = File.exists?(@registry_path)

    if had_file do
      File.copy!(@registry_path, backup_path)
    end

    Registry.clear()

    on_exit(fn ->
      Registry.clear()

      # Restore backup if it existed
      if had_file do
        File.rename!(backup_path, @registry_path)
      else
        File.rm(@registry_path)
      end
    end)

    :ok
  end

  describe "registry file lifecycle" do
    test "save/0 creates registry.json when file does not exist" do
      # Remove the file if it exists
      File.rm(@registry_path)
      refute File.exists?(@registry_path)

      # Register a library
      entry = %{
        python_module: "test_lib",
        python_version: "1.0.0",
        elixir_module: "TestLib",
        generated_at: DateTime.utc_now(),
        path: "/tmp/test",
        files: ["test.ex"],
        stats: %{functions: 1, classes: 0, submodules: 0}
      }

      :ok = Registry.register("test_lib", entry)

      # Save should create the file
      assert :ok = Registry.save()
      assert File.exists?(@registry_path)

      # Verify content is valid JSON
      {:ok, content} = File.read(@registry_path)
      {:ok, data} = Jason.decode(content)
      assert Map.has_key?(data, "libraries")
      assert Map.has_key?(data["libraries"], "test_lib")
    end

    test "load/0 handles missing registry.json gracefully" do
      # Remove the file
      File.rm(@registry_path)
      refute File.exists?(@registry_path)

      # Load should succeed with empty registry
      assert :ok = Registry.load()
      assert Registry.list_libraries() == []
    end

    test "registry directory is created if missing" do
      registry_dir = Path.dirname(@registry_path)

      # Temporarily remove the directory structure
      if File.exists?(@registry_path), do: File.rm!(@registry_path)
      if File.dir?(registry_dir), do: File.rmdir(registry_dir)

      entry = %{
        python_module: "test_lib",
        python_version: "1.0.0",
        elixir_module: "TestLib",
        generated_at: DateTime.utc_now(),
        path: "/tmp/test",
        files: ["test.ex"],
        stats: %{functions: 1, classes: 0, submodules: 0}
      }

      :ok = Registry.register("test_lib", entry)

      # Save should create the directory and file
      assert :ok = Registry.save()
      assert File.exists?(@registry_path)
    end
  end
end
