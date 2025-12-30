defmodule SnakeBridge.MethodSanitizationTest do
  use ExUnit.Case, async: true

  describe "method name sanitization" do
    test "sanitizes reserved word methods" do
      {elixir_name, python_name} = SnakeBridge.Generator.sanitize_method_name("class")
      assert elixir_name == "py_class"
      assert python_name == "class"
    end

    test "__init__ becomes new" do
      {elixir_name, python_name} = SnakeBridge.Generator.sanitize_method_name("__init__")
      assert elixir_name == "new"
      assert python_name == "__init__"
    end
  end
end
