defmodule SnakeBridge.Generator.TypespecTest do
  use ExUnit.Case, async: true

  test "generated specs reference Snakepit types and errors" do
    library = %SnakeBridge.Config.Library{
      name: :sympy,
      python_name: "sympy",
      module_name: Sympy,
      version: "~> 1.12"
    }

    functions = [
      %{
        "name" => "solve",
        "parameters" => [%{"name" => "expr", "kind" => "POSITIONAL_OR_KEYWORD"}],
        "return_annotation" => "Any"
      }
    ]

    classes = [
      %{
        "name" => "Symbol",
        "methods" => [
          %{
            "name" => "__init__",
            "parameters" => [%{"name" => "name", "kind" => "POSITIONAL_OR_KEYWORD"}]
          },
          %{
            "name" => "simplify",
            "parameters" => []
          }
        ],
        "attributes" => ["name"]
      }
    ]

    source = SnakeBridge.Generator.render_library(library, functions, classes, version: "3.0.0")

    assert source =~ "Snakepit.Error.t()"
    assert source =~ "Snakepit.PyRef.t()"
  end
end
