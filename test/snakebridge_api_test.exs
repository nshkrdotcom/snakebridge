defmodule SnakeBridgeAPITest do
  use ExUnit.Case, async: true

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
      config = SnakeBridge.TestFixtures.sample_config()
      assert {:ok, modules} = SnakeBridge.generate(config)
      assert is_list(modules)
      assert length(modules) > 0
    end
  end

  describe "integrate/2" do
    test "discovers and generates in one step" do
      assert {:ok, modules} = SnakeBridge.integrate("dspy")
      assert is_list(modules)
    end

    test "returns config along with modules" do
      assert {:ok, %{config: config, modules: modules}} =
               SnakeBridge.integrate("dspy", return: :full)

      assert %SnakeBridge.Config{} = config
      assert is_list(modules)
    end
  end
end
