defmodule SnakeBridge.Discovery.IntrospectorTest do
  use ExUnit.Case, async: true

  import Mox

  alias SnakeBridge.Discovery.Introspector
  alias SnakeBridge.Discovery.IntrospectorMock
  alias SnakeBridge.TestFixtures

  setup :verify_on_exit!

  describe "discover/2" do
    test "successfully discovers library schema" do
      module_path = "demo"
      expected_response = TestFixtures.sample_introspection_response()

      IntrospectorMock
      |> expect(:discover, fn ^module_path, _opts ->
        {:ok, expected_response}
      end)

      assert {:ok, schema} = Introspector.discover(IntrospectorMock, module_path, [])
      assert schema["library_version"] == "1.0.0"
      assert is_map(schema["classes"])
      assert Map.has_key?(schema["classes"], "Predict")
    end

    test "handles discovery errors gracefully" do
      IntrospectorMock
      |> expect(:discover, fn _module, _opts ->
        {:error, "Module not found"}
      end)

      assert {:error, "Module not found"} =
               Introspector.discover(IntrospectorMock, "nonexistent", [])
    end

    test "respects discovery depth option" do
      IntrospectorMock
      |> expect(:discover, fn _module, opts ->
        assert Keyword.get(opts, :depth) == 3
        {:ok, TestFixtures.sample_introspection_response()}
      end)

      Introspector.discover(IntrospectorMock, "demo", depth: 3)
    end

    test "uses cache when config_hash matches" do
      cached_hash = :crypto.hash(:sha256, "cached") |> Base.encode16(case: :lower)

      IntrospectorMock
      |> expect(:discover, fn _module, opts ->
        assert Keyword.get(opts, :config_hash) == cached_hash
        {:ok, %{cached: true}}
      end)

      Introspector.discover(IntrospectorMock, "demo", config_hash: cached_hash)
    end
  end

  describe "parse_descriptor/1" do
    test "normalizes Python descriptor to SnakeBridge format" do
      python_descriptor = TestFixtures.sample_class_descriptor()

      normalized = Introspector.parse_descriptor(python_descriptor)

      assert normalized.python_path == "demo.Predict"
      assert is_list(normalized.methods)
      assert length(normalized.methods) > 0
    end

    test "handles missing optional fields" do
      minimal_descriptor = %{
        name: "Simple",
        python_path: "test.Simple"
      }

      normalized = Introspector.parse_descriptor(minimal_descriptor)

      assert normalized.python_path == "test.Simple"
      assert normalized.methods == []
      assert normalized.docstring == ""
    end
  end
end
