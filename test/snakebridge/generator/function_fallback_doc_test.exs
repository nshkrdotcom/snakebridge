defmodule SnakeBridge.Generator.FunctionFallbackDocTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator.Function

  defp base_library do
    %SnakeBridge.Config.Library{
      name: :mylib,
      python_name: "mylib",
      module_name: Mylib
    }
  end

  test "uses fallback docstrings when function docs are missing" do
    info = %{
      "name" => "hello",
      "python_name" => "hello",
      "python_module" => "mylib",
      "docstring" => nil,
      "parameters" => [%{"name" => "value", "kind" => "POSITIONAL_OR_KEYWORD"}],
      "return_type" => %{"type" => "int"}
    }

    source = Function.render_function(info, base_library())

    assert source =~ "@doc"
    assert source =~ "Python binding for `mylib.hello`."
    assert source =~ "Parameters:"
  end

  test "uses fallback docstrings for module attributes" do
    info = %{
      "name" => "pi",
      "python_name" => "pi",
      "python_module" => "mylib",
      "docstring" => "",
      "type" => "attribute",
      "return_type" => %{"type" => "float"}
    }

    source = Function.render_function(info, base_library())

    assert source =~ "@doc"
    assert source =~ "Python module attribute `mylib.pi`."
  end
end
