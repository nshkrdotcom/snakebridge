defmodule SnakeBridge.ManifestTest do
  use ExUnit.Case, async: true

  test "missing ignores calls into class modules already in manifest" do
    manifest = %{
      "symbols" => %{},
      "classes" => %{
        "Sympy.Symbol" => %{"module" => "Sympy.Symbol", "class" => "Symbol"}
      }
    }

    detected = [{Sympy.Symbol, :simplify, 1}]

    assert SnakeBridge.Manifest.missing(manifest, detected) == []
  end

  @tag :tmp_dir
  test "load normalizes legacy Elixir-prefixed symbol keys", %{tmp_dir: tmp_dir} do
    config = %SnakeBridge.Config{metadata_dir: tmp_dir}
    path = Path.join(tmp_dir, "manifest.json")

    manifest = %{
      "version" => "0.7.2",
      "symbols" => %{
        "Elixir.Testlib.compute/1" => %{
          "module" => "Testlib",
          "function" => "compute",
          "name" => "compute",
          "python_module" => "testlib"
        }
      },
      "classes" => %{}
    }

    File.write!(path, Jason.encode!(manifest))

    loaded = SnakeBridge.Manifest.load(config)

    assert Map.has_key?(loaded["symbols"], "Testlib.compute/1")
    refute Map.has_key?(loaded["symbols"], "Elixir.Testlib.compute/1")
  end
end
