defmodule SnakeBridgeAPITest do
  use ExUnit.Case, async: false

  alias SnakeBridge

  describe "discover/2" do
    test "discovers a Python library schema" do
      assert {:ok, schema} = SnakeBridge.discover("dspy")
      assert is_map(schema)
      assert Map.has_key?(schema, "library_version")
    end

    test "passes options to discovery" do
      assert {:ok, _schema} = SnakeBridge.discover("dspy", depth: 3)
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
      purge_module(:"Dspy.Predict")
      purge_module(:"Dspy.Settings")

      on_exit(fn ->
        purge_module(:"Dspy.Predict")
        purge_module(:"Dspy.Settings")
      end)

      assert {:ok, modules} = SnakeBridge.integrate("dspy")
      assert is_list(modules)
    end

    test "returns config along with modules" do
      # Cleanup any existing modules before and after test
      purge_module(:"Dspy.Predict")
      purge_module(:"Dspy.Settings")

      on_exit(fn ->
        purge_module(:"Dspy.Predict")
        purge_module(:"Dspy.Settings")
      end)

      assert {:ok, %{config: config, modules: modules}} =
               SnakeBridge.integrate("dspy", return: :full)

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
