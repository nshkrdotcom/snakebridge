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
    assert source =~ "SnakeBridge.Ref.t()"
  end

  test "generated specs use mapped types when available" do
    library = %SnakeBridge.Config.Library{
      name: :math,
      python_name: "math",
      module_name: Math,
      version: "~> 1.0"
    }

    functions = [
      %{
        "name" => "sum",
        "parameters" => [
          %{
            "name" => "values",
            "kind" => "POSITIONAL_OR_KEYWORD",
            "type" => %{"type" => "list", "element_type" => %{"type" => "int"}}
          }
        ],
        "return_type" => %{"type" => "int"}
      }
    ]

    source = SnakeBridge.Generator.render_library(library, functions, [], version: "3.0.0")

    assert source =~
             "@spec sum(list(integer()), keyword()) :: {:ok, integer()} | {:error, Snakepit.Error.t()}"
  end
end
