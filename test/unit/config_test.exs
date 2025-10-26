defmodule SnakeBridge.ConfigTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Config
  alias SnakeBridge.TestFixtures

  describe "Config validation" do
    test "validates a valid configuration" do
      config = TestFixtures.sample_config()

      assert {:ok, validated} = Config.validate(config)
      assert validated.python_module == "dspy"
      assert validated.version == "2.5.0"
    end

    test "requires python_module field" do
      config = %Config{version: "1.0.0"}

      assert {:error, errors} = Config.validate(config)
      assert "python_module is required" in errors
    end

    test "validates introspection settings" do
      config = %Config{
        python_module: "test",
        introspection: %{
          enabled: true,
          cache_path: "/valid/path.json",
          discovery_depth: 3
        }
      }

      assert {:ok, _} = Config.validate(config)
    end

    test "rejects invalid discovery_depth" do
      config = %Config{
        python_module: "test",
        introspection: %{
          discovery_depth: -1
        }
      }

      assert {:error, errors} = Config.validate(config)
      assert Enum.any?(errors, &String.contains?(&1, "discovery_depth"))
    end

    test "validates class configurations" do
      config = %Config{
        python_module: "test",
        classes: [
          %{
            python_path: "test.MyClass",
            elixir_module: Test.MyClass,
            constructor: %{args: %{}, session_aware: true},
            methods: []
          }
        ]
      }

      assert {:ok, _} = Config.validate(config)
    end

    test "rejects classes without python_path" do
      config = %Config{
        python_module: "test",
        classes: [
          %{
            elixir_module: Test.MyClass
          }
        ]
      }

      assert {:error, errors} = Config.validate(config)
      assert Enum.any?(errors, &String.contains?(&1, "python_path"))
    end
  end

  describe "Config composition" do
    test "merges configurations with extends" do
      base = %Config{
        python_module: "base",
        classes: [
          %{
            python_path: "base.Class",
            elixir_module: Base.Class,
            methods: [%{name: "base_method"}]
          }
        ]
      }

      extending = %Config{
        python_module: "extending",
        extends: base,
        classes: [
          %{
            python_path: "extending.Class",
            elixir_module: Extending.Class,
            methods: [%{name: "new_method"}]
          }
        ]
      }

      merged = Config.compose(extending)

      assert length(merged.classes) == 2
      assert Enum.any?(merged.classes, &(&1.python_path == "base.Class"))
      assert Enum.any?(merged.classes, &(&1.python_path == "extending.Class"))
    end

    test "applies mixins to configuration" do
      mixin = %{
        telemetry: %{enabled: true},
        timeout: 30_000
      }

      config = %Config{
        python_module: "test",
        mixins: [mixin],
        # Override
        timeout: 60_000
      }

      composed = Config.compose(config)

      assert composed.telemetry.enabled == true
      # Override takes precedence
      assert composed.timeout == 60_000
    end

    test "deep merges nested configurations" do
      mixin = %{
        telemetry: %{enabled: true, tags: %{domain: "ml"}}
      }

      config = %Config{
        python_module: "test",
        mixins: [mixin],
        telemetry: %{tags: %{family: "dspy"}}
      }

      composed = Config.compose(config)

      assert composed.telemetry.enabled == true
      assert composed.telemetry.tags.domain == "ml"
      assert composed.telemetry.tags.family == "dspy"
    end
  end

  describe "Config serialization" do
    test "converts config to elixir code" do
      config = TestFixtures.sample_config()

      code = Config.to_elixir_code(config)

      assert is_binary(code)
      assert String.contains?(code, "%SnakeBridge.Config{")
      assert String.contains?(code, ~s(python_module: "dspy"))
    end

    test "pretty prints configuration" do
      config = TestFixtures.sample_config()

      formatted = Config.pretty_print(config)

      assert String.contains?(formatted, "python_module:")
      assert String.contains?(formatted, "classes:")
      assert String.contains?(formatted, "- dspy.Predict")
    end
  end

  describe "Config caching" do
    test "generates consistent hash for same config" do
      config = TestFixtures.sample_config()

      hash1 = Config.hash(config)
      hash2 = Config.hash(config)

      assert hash1 == hash2
      assert is_binary(hash1)
      # SHA256 hex
      assert byte_size(hash1) == 64
    end

    test "generates different hash for different configs" do
      config1 = %Config{python_module: "test1"}
      config2 = %Config{python_module: "test2"}

      hash1 = Config.hash(config1)
      hash2 = Config.hash(config2)

      assert hash1 != hash2
    end
  end
end
