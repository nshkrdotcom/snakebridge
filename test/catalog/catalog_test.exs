defmodule SnakeBridge.CatalogTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Catalog

  describe "list/0" do
    test "returns list of cataloged libraries" do
      libraries = Catalog.list()

      assert is_list(libraries)
      assert length(libraries) > 0
    end

    test "each entry has required fields" do
      libraries = Catalog.list()

      for lib <- libraries do
        assert is_atom(lib.name)
        assert is_binary(lib.description)
        # pypi_package can be nil for built-ins (like json)
        assert is_binary(lib.pypi_package) or is_nil(lib.pypi_package)
        assert is_binary(lib.import_name)
        assert is_binary(lib.version)
        assert lib.adapter in [:generic, :specialized]
        assert is_boolean(lib.supports_streaming)
        assert lib.status in [:tested, :beta, :experimental]
      end
    end

    test "includes genai library" do
      libraries = Catalog.list()
      genai = Enum.find(libraries, &(&1.name == :genai))

      assert genai != nil
      assert genai.pypi_package == "google-genai"
      assert genai.adapter == :specialized
      assert genai.supports_streaming == true
    end
  end

  describe "get/1" do
    test "retrieves library by name" do
      entry = Catalog.get(:genai)

      assert entry != nil
      assert entry.name == :genai
      assert entry.pypi_package == "google-genai"
    end

    test "returns nil for unknown library" do
      assert Catalog.get(:unknown_lib) == nil
    end
  end

  describe "by_category/1" do
    test "filters libraries by category" do
      llm_libs = Catalog.by_category(:llm)

      assert is_list(llm_libs)
      assert Enum.all?(llm_libs, &(&1.category == :llm))
    end
  end

  describe "streaming_libraries/0" do
    test "returns only streaming-capable libraries" do
      streaming = Catalog.streaming_libraries()

      assert is_list(streaming)
      assert Enum.all?(streaming, &(&1.supports_streaming == true))
      assert Enum.any?(streaming, &(&1.name == :genai))
    end
  end

  describe "install_command/1" do
    test "returns pip install command with version" do
      {:ok, cmd} = Catalog.install_command(:genai)

      assert cmd =~ "pip install"
      assert cmd =~ "google-genai"
      # Has version
      assert cmd =~ "0.3" or cmd =~ "=="
    end

    test "returns error for unknown library" do
      assert {:error, :not_in_catalog} = Catalog.install_command(:unknown)
    end
  end

  describe "adapter_config/1" do
    test "returns adapter configuration for Snakepit" do
      {:ok, config} = Catalog.adapter_config(:genai)

      assert config.library == :genai
      assert config.use_specialized == true
      assert is_binary(config.python_module)
      assert is_binary(config.python_class)
      assert is_list(config.requires_env)
    end

    test "generic adapter for libraries without specialized adapter" do
      {:ok, config} = Catalog.adapter_config(:numpy)

      assert config.use_specialized == false
      assert config.python_module == "snakebridge_adapter.adapter"
      assert config.python_class == "SnakeBridgeAdapter"
    end
  end
end
