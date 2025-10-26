defmodule SnakeBridge.Property.ConfigTest do
  use ExUnit.Case
  use ExUnitProperties

  alias SnakeBridge.Config

  describe "Config property-based tests" do
    property "hash is consistent for same config" do
      check all(
              module_name <- string(:alphanumeric, min_length: 1),
              version <- string(:alphanumeric, min_length: 1)
            ) do
        config = %Config{
          python_module: module_name,
          version: version
        }

        hash1 = Config.hash(config)
        hash2 = Config.hash(config)

        assert hash1 == hash2
        assert is_binary(hash1)
        # SHA256 hex
        assert byte_size(hash1) == 64
      end
    end

    property "different configs have different hashes" do
      check all(
              module1 <- string(:alphanumeric, min_length: 1),
              module2 <- string(:alphanumeric, min_length: 1),
              module1 != module2
            ) do
        config1 = %Config{python_module: module1}
        config2 = %Config{python_module: module2}

        hash1 = Config.hash(config1)
        hash2 = Config.hash(config2)

        assert hash1 != hash2
      end
    end

    property "serialization roundtrip preserves data" do
      check all(
              module_name <- string(:alphanumeric, min_length: 1),
              version <- string(:alphanumeric, min_length: 1)
            ) do
        original = %Config{
          python_module: module_name,
          version: version
        }

        # to_map -> from_map
        map = Config.to_map(original)
        {:ok, deserialized} = Config.from_map(map)

        assert deserialized.python_module == original.python_module
        assert deserialized.version == original.version
      end
    end
  end
end
