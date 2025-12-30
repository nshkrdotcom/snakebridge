defmodule SnakeBridge.VariadicWrapperTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator

  describe "C-extension signature handling" do
    test "empty parameters with signature_available false generates variadic" do
      info = %{
        "name" => "sqrt",
        "parameters" => [],
        "signature_available" => false
      }

      plan = Generator.build_params(info["parameters"], info)
      assert plan.is_variadic == true
      assert plan.has_args == true
      assert plan.has_opts == true
    end

    test "variadic wrapper generates multiple arity clauses" do
      info = %{
        "name" => "sqrt",
        "parameters" => [],
        "signature_available" => false,
        "docstring" => "Square root."
      }

      library = %SnakeBridge.Config.Library{
        name: :math,
        python_name: "math",
        module_name: Math,
        streaming: []
      }

      source = Generator.render_function(info, library)

      assert source =~ "def sqrt()"
      assert source =~ "def sqrt(arg1)"
      assert source =~ "def sqrt(arg1, arg2)"
    end
  end
end
