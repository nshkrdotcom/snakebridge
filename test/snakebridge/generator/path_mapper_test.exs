defmodule SnakeBridge.Generator.PathMapperTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator.PathMapper

  describe "module_to_path/2" do
    test "root module uses __init__.ex" do
      assert PathMapper.module_to_path("dspy", "lib/gen") == "lib/gen/dspy/__init__.ex"
    end

    test "single submodule uses __init__.ex" do
      assert PathMapper.module_to_path("dspy.predict", "lib/gen") ==
               "lib/gen/dspy/predict/__init__.ex"
    end

    test "deep submodule uses __init__.ex" do
      assert PathMapper.module_to_path("dspy.predict.chain", "lib/gen") ==
               "lib/gen/dspy/predict/chain/__init__.ex"
    end

    test "class/leaf module uses .ex file" do
      # When we know it's a class or leaf, we use direct .ex
      assert PathMapper.module_to_path("dspy.predict.rlm", "lib/gen", :leaf) ==
               "lib/gen/dspy/predict/rlm.ex"
    end

    test "handles dotted library names" do
      assert PathMapper.module_to_path("torch.nn", "lib/gen") == "lib/gen/torch/nn/__init__.ex"

      assert PathMapper.module_to_path("torch.nn.functional", "lib/gen") ==
               "lib/gen/torch/nn/functional/__init__.ex"
    end

    test "handles trailing slash in base_dir" do
      assert PathMapper.module_to_path("numpy", "lib/gen/") == "lib/gen/numpy/__init__.ex"
    end
  end

  describe "module_to_dir/2" do
    test "root module returns module directory" do
      assert PathMapper.module_to_dir("dspy", "lib/gen") == "lib/gen/dspy"
    end

    test "submodule returns nested directory" do
      assert PathMapper.module_to_dir("dspy.predict", "lib/gen") == "lib/gen/dspy/predict"
    end

    test "deep module returns full path" do
      assert PathMapper.module_to_dir("dspy.predict.rlm", "lib/gen") ==
               "lib/gen/dspy/predict/rlm"
    end
  end

  describe "ancestor_modules/1" do
    test "root has no ancestors" do
      assert PathMapper.ancestor_modules("dspy") == []
    end

    test "single depth has one ancestor" do
      assert PathMapper.ancestor_modules("dspy.predict") == ["dspy"]
    end

    test "multiple depth has ordered ancestors" do
      assert PathMapper.ancestor_modules("dspy.predict.chain.rlm") == [
               "dspy",
               "dspy.predict",
               "dspy.predict.chain"
             ]
    end
  end

  describe "python_module_to_elixir_module/2" do
    test "converts python module path to elixir module" do
      assert PathMapper.python_module_to_elixir_module("dspy", Dspy) == Dspy
    end

    test "converts submodule to nested elixir module" do
      assert PathMapper.python_module_to_elixir_module("dspy.predict", Dspy) == Dspy.Predict
    end

    test "converts deep submodule" do
      assert PathMapper.python_module_to_elixir_module("dspy.predict.rlm", Dspy) ==
               Dspy.Predict.Rlm
    end

    test "handles dotted library base" do
      assert PathMapper.python_module_to_elixir_module("torch.nn.functional", Torch.NN) ==
               Torch.NN.Functional
    end
  end

  describe "class_file_path/3" do
    test "class file uses .ex extension in module directory" do
      # Class in dspy.predict module named RLM -> dspy/predict/rlm.ex
      result = PathMapper.class_file_path("dspy.predict", "RLM", "lib/gen")
      assert result == "lib/gen/dspy/predict/rlm.ex"
    end

    test "class in root module" do
      result = PathMapper.class_file_path("dspy", "Module", "lib/gen")
      assert result == "lib/gen/dspy/module.ex"
    end

    test "class with underscored name" do
      result = PathMapper.class_file_path("dspy.predict", "ChainOfThought", "lib/gen")
      assert result == "lib/gen/dspy/predict/chain_of_thought.ex"
    end
  end

  describe "all_files_for_library/4" do
    test "computes all files for functions and classes" do
      functions = [
        %{"python_module" => "dspy"},
        %{"python_module" => "dspy.predict"}
      ]

      classes = [
        %{"python_module" => "dspy.predict", "name" => "RLM"}
      ]

      {module_files, class_files} =
        PathMapper.all_files_for_library("dspy", functions, classes, "lib/gen")

      assert "lib/gen/dspy/__init__.ex" in module_files
      assert "lib/gen/dspy/predict/__init__.ex" in module_files
      assert "lib/gen/dspy/predict/rlm.ex" in class_files
    end

    test "module files include class modules without functions" do
      classes = [
        %{"python_module" => "dspy.predict", "name" => "RLM"}
      ]

      {module_files, class_files} =
        PathMapper.all_files_for_library("dspy", [], classes, "lib/gen")

      assert "lib/gen/dspy/__init__.ex" in module_files
      assert "lib/gen/dspy/predict/__init__.ex" in module_files
      assert "lib/gen/dspy/predict/rlm.ex" in class_files
    end

    test "module files include root and function modules only" do
      functions = [
        %{"python_module" => "dspy.predict.rlm"}
      ]

      {module_files, _class_files} =
        PathMapper.all_files_for_library("dspy", functions, [], "lib/gen")

      assert "lib/gen/dspy/__init__.ex" in module_files
      assert "lib/gen/dspy/predict/rlm/__init__.ex" in module_files
      refute "lib/gen/dspy/predict/__init__.ex" in module_files
    end
  end
end
