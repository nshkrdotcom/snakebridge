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

  test "generated class methods skip self parameter" do
    library = %SnakeBridge.Config.Library{
      name: :mylib,
      python_name: "mylib",
      module_name: Mylib
    }

    classes = [
      %{
        "name" => "Thing",
        "python_module" => "mylib",
        "methods" => [
          %{
            "name" => "do_it",
            "parameters" => [
              %{"name" => "self", "kind" => "POSITIONAL_OR_KEYWORD"},
              %{"name" => "value", "kind" => "POSITIONAL_OR_KEYWORD"}
            ]
          }
        ],
        "attributes" => []
      }
    ]

    source = SnakeBridge.Generator.render_library(library, [], classes, version: "3.0.0")

    assert source =~ "def do_it(ref, value"
    refute source =~ "def do_it(ref, self"
  end

  test "generated class methods skip cls parameter" do
    library = %SnakeBridge.Config.Library{
      name: :mylib,
      python_name: "mylib",
      module_name: Mylib
    }

    classes = [
      %{
        "name" => "Builder",
        "python_module" => "mylib",
        "methods" => [
          %{
            "name" => "build",
            "parameters" => [
              %{"name" => "cls", "kind" => "POSITIONAL_OR_KEYWORD"},
              %{"name" => "value", "kind" => "POSITIONAL_OR_KEYWORD"}
            ]
          }
        ],
        "attributes" => []
      }
    ]

    source = SnakeBridge.Generator.render_library(library, [], classes, version: "3.0.0")

    assert source =~ "def build(ref, value"
    refute source =~ "def build(ref, cls"
  end
end
