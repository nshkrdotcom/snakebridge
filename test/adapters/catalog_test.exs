defmodule SnakeBridge.Adapters.CatalogTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Adapters.Catalog

  describe "list/0" do
    test "returns list of available adapters" do
      adapters = Catalog.list()

      assert is_list(adapters)
      assert length(adapters) > 0

      # Each adapter has required fields
      for adapter <- adapters do
        assert Map.has_key?(adapter, :name)
        assert Map.has_key?(adapter, :description)
        assert Map.has_key?(adapter, :module)
      end
    end

    test "includes genai adapter" do
      adapters = Catalog.list()
      genai = Enum.find(adapters, &(&1.name == :genai))

      assert genai != nil
      assert genai.description =~ "GenAI"
    end
  end

  describe "get/1" do
    test "retrieves adapter by name" do
      adapter_module = Catalog.get(:genai)

      assert adapter_module != nil
      assert function_exported?(adapter_module, :adapter_config, 0)
    end

    test "returns nil for unknown adapter" do
      assert Catalog.get(:nonexistent_adapter) == nil
    end
  end

  describe "adapter_config/1" do
    test "returns adapter configuration" do
      {:ok, config} = Catalog.adapter_config(:genai)

      assert config.name == :genai
      assert config.python_module != nil
      assert config.python_class != nil
      assert is_list(config.requires_packages)
      assert is_list(config.requires_env)
      assert is_boolean(config.supports_streaming)
    end

    test "returns error for unknown adapter" do
      assert {:error, :adapter_not_found} = Catalog.adapter_config(:unknown)
    end
  end
end
