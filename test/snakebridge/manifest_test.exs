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
end
