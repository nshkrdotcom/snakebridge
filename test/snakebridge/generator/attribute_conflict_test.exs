defmodule SnakeBridge.Generator.AttributeConflictTest do
  use ExUnit.Case, async: true

  test "attributes that collide with methods are suffixed" do
    library = %SnakeBridge.Config.Library{
      name: :dspy,
      python_name: "dspy",
      module_name: Dspy,
      version: "3.1.2"
    }

    classes = [
      %{
        "name" => "Tokens",
        "python_module" => "dspy.dsp.utils.dpr",
        "methods" => [
          %{"name" => "pos", "parameters" => []}
        ],
        "attributes" => ["POS"]
      }
    ]

    source = SnakeBridge.Generator.render_library(library, [], classes, version: "3.0.0")

    assert source =~ "def pos(ref, opts \\\\ [])"
    assert source =~ "def pos_attr(ref)"
    assert source =~ "get_attr(ref, :POS)"
  end
end
