defmodule SnakeBridge.PipelineClassModuleTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Compiler.Pipeline
  alias SnakeBridge.Config.Library

  test "prefers class modules over module wrappers" do
    library = %Library{
      name: :examplelib,
      python_name: "examplelib",
      module_name: Examplelib,
      version: "1.0.0"
    }

    reserved_modules = MapSet.new([Examplelib.Core.Utils.Settings])

    class_module =
      Pipeline.test_class_module_for(
        library,
        "examplelib.core.utils.settings",
        "Settings",
        reserved_modules,
        MapSet.new()
      )

    assert class_module == Examplelib.Core.Utils.Settings
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
      name: :examplelib,
      python_name: "examplelib",
      module_name: Examplelib,
      version: "1.0.0"
    }

    class_module =
      Pipeline.test_class_module_for(
        library,
        "examplelib.core.utils.utils",
        "dotdict",
        MapSet.new(),
        MapSet.new()
      )

    assert class_module == Examplelib.Core.Utils.Utils.Dotdict
  end
end
