defmodule SnakeBridge.PipelineClassModuleTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Compiler.Pipeline
  alias SnakeBridge.Config.Library

  test "avoids class/module collisions when module wrapper exists" do
    library = %Library{
      name: :dspy,
      python_name: "dspy",
      module_name: Dspy,
      version: "3.1.2"
    }

    reserved_modules = MapSet.new([Dspy.Dsp.Utils.Settings])

    class_module =
      Pipeline.test_class_module_for(
        library,
        "dspy.dsp.utils.settings",
        "Settings",
        reserved_modules,
        MapSet.new()
      )

    assert class_module == Dspy.Dsp.Utils.SettingsClass
  end

  test "keeps compact class modules when no module wrapper exists" do
    library = %Library{
      name: :sympy,
      python_name: "sympy",
      module_name: Sympy,
      version: "~> 1.12"
    }

    class_module =
      Pipeline.test_class_module_for(
        library,
        "sympy.core.symbol",
        "Symbol",
        MapSet.new(),
        MapSet.new()
      )

    assert class_module == Sympy.Core.Symbol
  end

  test "camelizes lowercase class names" do
    library = %Library{
      name: :dspy,
      python_name: "dspy",
      module_name: Dspy,
      version: "3.1.2"
    }

    class_module =
      Pipeline.test_class_module_for(
        library,
        "dspy.dsp.utils.utils",
        "dotdict",
        MapSet.new(),
        MapSet.new()
      )

    assert class_module == Dspy.Dsp.Utils.Utils.Dotdict
  end
end
