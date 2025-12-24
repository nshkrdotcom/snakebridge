defmodule SnakeBridgeAPITest do
  use ExUnit.Case, async: false

  alias SnakeBridge

  setup do
    purge_module(:"Demo.Predict")
    purge_module(:"Demo.Settings")
    purge_module(:"Demo.SettingsFunctions")
    purge_module(Demo.Predict)
    purge_module(Demo.Settings)
    purge_module(Demo.SettingsFunctions)
    :ok
  end

  describe "discover/2" do
    test "discovers a Python library schema" do
      assert {:ok, schema} = SnakeBridge.discover("demo")
      assert is_map(schema)
      assert Map.has_key?(schema, "library_version")
    end

    test "passes options to discovery" do
      assert {:ok, _schema} = SnakeBridge.discover("demo", depth: 3)
    end
  end

  describe "generate/1" do
    test "generates modules from config" do
      suffix = SnakeBridge.TestFixtures.unique_module_suffix()
      config = SnakeBridge.TestFixtures.sample_config(suffix)
      assert {:ok, modules} = SnakeBridge.generate(config)
      assert is_list(modules)
      assert length(modules) > 0
    end
  end

  describe "integrate/2" do
    test "discovers and generates in one step" do
      # Cleanup any existing modules before and after test
      on_exit(fn ->
        purge_module(:"Demo.Predict")
        purge_module(:"Demo.Settings")
        purge_module(:"Demo.SettingsFunctions")
        purge_module(Demo.Predict)
        purge_module(Demo.Settings)
        purge_module(Demo.SettingsFunctions)
      end)

      assert {:ok, modules} = SnakeBridge.integrate("demo")
      assert is_list(modules)
    end

    test "returns config along with modules" do
      # Cleanup any existing modules before and after test
      on_exit(fn ->
        purge_module(:"Demo.Predict")
        purge_module(:"Demo.Settings")
        purge_module(:"Demo.SettingsFunctions")
        purge_module(Demo.Predict)
        purge_module(Demo.Settings)
        purge_module(Demo.SettingsFunctions)
      end)

      assert {:ok, %{config: config, modules: modules}} =
               SnakeBridge.integrate("demo", return: :full)

      assert %SnakeBridge.Config{} = config
      assert is_list(modules)
    end
  end

  # Helper to purge modules created during tests
  defp purge_module(module) do
    :code.purge(module)
    :code.delete(module)
  end
end
