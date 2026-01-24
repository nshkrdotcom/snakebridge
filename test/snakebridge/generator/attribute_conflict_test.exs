defmodule SnakeBridge.Generator.AttributeConflictTest do
  use ExUnit.Case, async: true

  test "attributes that collide with methods are suffixed" do
    library = %SnakeBridge.Config.Library{
      name: :examplelib,
      python_name: "examplelib",
      module_name: Examplelib,
      version: "1.0.0"
    }

    classes = [
      %{
        "name" => "Tokens",
        "python_module" => "examplelib.core.utils.dpr",
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

  test "attributes that collide with constructors are suffixed" do
    library = %SnakeBridge.Config.Library{
      name: :examplelib,
      python_name: "examplelib",
      module_name: Examplelib,
      version: "1.0.0"
    }

    classes = [
      %{
        "name" => "EngineState",
        "python_module" => "examplelib.engine",
        "methods" => [],
        "attributes" => ["NEW"]
      }
    ]

    source = SnakeBridge.Generator.render_library(library, [], classes, version: "3.0.0")

    assert source =~ "def new(opts \\\\ [])"
    assert source =~ "def new_attr(ref)"
    assert source =~ "get_attr(ref, :NEW)"
  end
end
