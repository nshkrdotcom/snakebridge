defmodule SnakeBridge.Generator.ClassSubmoduleTest do
  use ExUnit.Case, async: true

  test "class modules use python_module and avoid duplicate submodule names" do
    library = %SnakeBridge.Config.Library{
      name: :sympy,
      python_name: "sympy",
      module_name: Sympy,
      version: "~> 1.12"
    }

    classes = [
      %{
        "name" => "Symbol",
        "python_module" => "sympy.core.symbol",
        "methods" => [],
        "attributes" => []
      }
    ]

    source = SnakeBridge.Generator.render_library(library, [], classes, version: "3.0.0")

    assert source =~ "defmodule Sympy do"
    assert source =~ "defmodule Core.Symbol do"
    assert source =~ "def __snakebridge_python_name__, do: \"sympy.core.symbol\""
    assert source =~ "def __snakebridge_library__, do: \"sympy\""
    refute source =~ "defmodule Core.Symbol.Symbol"
  end
end
