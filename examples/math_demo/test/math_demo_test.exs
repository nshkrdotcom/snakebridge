defmodule MathDemoTest do
  use ExUnit.Case

  describe "generated modules" do
    test "Math module is generated and has functions" do
      functions = Math.__functions__()
      assert is_list(functions)
      assert length(functions) > 0

      # Check for expected functions
      names = Enum.map(functions, fn {name, _, _, _} -> name end)
      assert :sqrt in names
      assert :sin in names
      assert :cos in names
    end

    test "Json module is generated and has functions" do
      functions = Json.__functions__()
      assert is_list(functions)

      names = Enum.map(functions, fn {name, _, _, _} -> name end)
      assert :dumps in names
      assert :loads in names
    end

    test "Json module has classes" do
      classes = Json.__classes__()
      assert is_list(classes)
      assert length(classes) > 0
    end

    test "search works" do
      results = Math.__search__("sqrt")
      assert length(results) >= 1

      {name, _arity, _mod, _doc} = hd(results)
      assert name == :sqrt
    end
  end

  describe "MathDemo helpers" do
    test "generated_structure returns adapter entries" do
      {:ok, info} = MathDemo.generated_structure()
      assert is_map(info.adapters)
      assert Map.has_key?(info.adapters, "math")
      assert Map.has_key?(info.adapters, "json")
    end

    test "discover returns :ok" do
      assert :ok == MathDemo.discover()
    end
  end
end
