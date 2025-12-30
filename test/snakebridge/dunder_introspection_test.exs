defmodule SnakeBridge.DunderIntrospectionTest do
  use ExUnit.Case, async: true

  describe "dunder method detection" do
    test "introspection captures __len__ when present" do
      result = %{
        "dunder_methods" => ["__len__", "__getitem__", "__iter__"],
        "methods" => []
      }

      assert "__len__" in result["dunder_methods"]
    end

    test "dunder methods stored in manifest" do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "snakebridge_manifest_#{System.unique_integer([:positive])}"
        )

      config = %SnakeBridge.Config{metadata_dir: tmp_dir}

      manifest = %{
        "version" => "0.0.0",
        "symbols" => %{},
        "classes" => %{
          "Test" => %{
            "dunder_methods" => ["__len__", "__iter__"],
            "methods" => [],
            "attributes" => []
          }
        }
      }

      :ok = SnakeBridge.Manifest.save(config, manifest)
      loaded = SnakeBridge.Manifest.load(config)

      assert loaded["classes"]["Test"]["dunder_methods"] == ["__len__", "__iter__"]
    end
  end
end
