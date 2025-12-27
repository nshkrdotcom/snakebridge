defmodule SnakeBridge.HelperGeneratorTest do
  use ExUnit.Case, async: true

  test "renders helper modules grouped by library and namespace" do
    helpers = [
      %{
        "name" => "sympy.parse_implicit",
        "parameters" => [%{"name" => "expr", "kind" => "POSITIONAL_OR_KEYWORD"}],
        "docstring" => "Parse implicit expression"
      },
      %{
        "name" => "sympy.parsing.parse_explicit",
        "parameters" => [],
        "docstring" => "Parse explicit expression"
      }
    ]

    source = SnakeBridge.HelperGenerator.render_library("sympy", helpers, version: "0.1.0")

    assert source =~ "defmodule Sympy.Helpers"
    assert source =~ "def parse_implicit"
    assert source =~ "SnakeBridge.Runtime.call_helper(\"sympy.parse_implicit\""

    assert source =~ "defmodule Sympy.Helpers.Parsing"
    assert source =~ "def parse_explicit"
    assert source =~ "SnakeBridge.Runtime.call_helper(\"sympy.parsing.parse_explicit\""
  end
end
