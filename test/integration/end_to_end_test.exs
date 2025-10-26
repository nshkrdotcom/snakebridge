defmodule SnakeBridge.Integration.EndToEndTest do
  use ExUnit.Case

  alias SnakeBridge.{Config, Discovery, Generator, Runtime}
  alias SnakeBridge.TestFixtures

  @moduletag :integration

  describe "full integration workflow" do
    @tag :slow
    test "discover -> generate -> execute workflow" do
      # Step 1: Discover library schema (mocked for now)
      {:ok, schema} = Discovery.discover("test_library", [])

      assert is_map(schema)
      assert Map.has_key?(schema, "classes")

      # Step 2: Generate configuration from schema
      config = Discovery.schema_to_config(schema, python_module: "test_library")

      assert config.python_module == "test_library"
      assert is_list(config.classes)

      # Step 3: Generate Elixir modules
      {:ok, modules} = Generator.generate_all(config)

      assert is_list(modules)
      assert length(modules) > 0

      # Step 4: Execute generated module (with mock runtime)
      # This would actually call Python in production
      [first_module | _] = modules

      assert {:ok, instance_ref} = first_module.create(%{signature: "test -> output"})
      assert is_tuple(instance_ref)
    end

    test "config -> cache -> reload workflow" do
      config = TestFixtures.sample_config()

      # Save to cache
      {:ok, cache_path} = SnakeBridge.Cache.store(config)
      assert File.exists?(cache_path)

      # Load from cache
      {:ok, loaded_config} = SnakeBridge.Cache.load(cache_path)
      assert loaded_config.python_module == config.python_module

      # Verify hash matches
      assert Config.hash(config) == Config.hash(loaded_config)

      # Cleanup
      File.rm(cache_path)
    end

    test "diff -> incremental regeneration workflow" do
      old_config = TestFixtures.sample_config()
      new_config = %{old_config | version: "2.6.0"}

      # Generate initial modules
      {:ok, old_modules} = Generator.generate_all(old_config)

      # Compute diff
      diff = SnakeBridge.Schema.Differ.diff(old_config, new_config)

      # Regenerate only changed modules
      {:ok, updated_modules} = Generator.generate_incremental(diff, old_modules)

      # Should be faster than full regeneration
      assert length(updated_modules) <= length(old_modules)
    end
  end

  describe "error handling across layers" do
    test "handles discovery failures gracefully" do
      assert {:error, _reason} = Discovery.discover("nonexistent_module", [])
    end

    test "validates config before generation" do
      invalid_config = %Config{python_module: ""}

      assert {:error, _errors} = Generator.generate_all(invalid_config)
    end

    test "provides helpful error messages" do
      {:error, errors} = Config.validate(%Config{})

      assert is_list(errors)
      assert Enum.all?(errors, &is_binary/1)
      assert Enum.any?(errors, &String.contains?(&1, "python_module"))
    end
  end
end
