defmodule SnakeBridge.Generator.TypeMapperTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator.TypeMapper

  describe "to_spec/1 with primitive types" do
    test "maps int to integer()" do
      python_type = %{"type" => "int"}
      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "integer()"
    end

    test "maps str to String.t()" do
      python_type = %{"type" => "str"}
      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "String.t()"
    end

    test "maps float to float()" do
      python_type = %{"type" => "float"}
      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "float()"
    end

    test "maps bool to boolean()" do
      python_type = %{"type" => "bool"}
      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "boolean()"
    end

    test "maps bytes to binary()" do
      python_type = %{"type" => "bytes"}
      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "binary()"
    end

    test "maps none to nil" do
      python_type = %{"type" => "none"}
      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "nil"
    end

    test "maps any to term()" do
      python_type = %{"type" => "any"}
      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "term()"
    end
  end

  describe "to_spec/1 with collection types" do
    test "maps list of integers to list(integer())" do
      python_type = %{
        "type" => "list",
        "element_type" => %{"type" => "int"}
      }

      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "list(integer())"
    end

    test "maps list of any to list(term())" do
      python_type = %{
        "type" => "list",
        "element_type" => %{"type" => "any"}
      }

      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "list(term())"
    end

    test "maps dict to map()" do
      python_type = %{
        "type" => "dict",
        "key_type" => %{"type" => "str"},
        "value_type" => %{"type" => "int"}
      }

      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "%{optional(String.t()) => integer()}"
    end

    test "maps tuple with element types" do
      python_type = %{
        "type" => "tuple",
        "element_types" => [
          %{"type" => "int"},
          %{"type" => "str"}
        ]
      }

      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "{integer(), String.t()}"
    end

    test "maps empty tuple" do
      python_type = %{
        "type" => "tuple",
        "element_types" => []
      }

      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "{}"
    end

    test "maps set to MapSet.t()" do
      python_type = %{
        "type" => "set",
        "element_type" => %{"type" => "str"}
      }

      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "MapSet.t(String.t())"
    end
  end

  describe "to_spec/1 with union types" do
    test "maps optional type to union with nil" do
      python_type = %{
        "type" => "optional",
        "inner_type" => %{"type" => "str"}
      }

      spec_ast = TypeMapper.to_spec(python_type)

      result = Macro.to_string(spec_ast)
      assert result == "String.t() | nil" or result == "nil | String.t()"
    end

    test "maps union of multiple types" do
      python_type = %{
        "type" => "union",
        "types" => [
          %{"type" => "int"},
          %{"type" => "str"},
          %{"type" => "bool"}
        ]
      }

      spec_ast = TypeMapper.to_spec(python_type)

      result = Macro.to_string(spec_ast)
      assert result =~ "integer()"
      assert result =~ "String.t()"
      assert result =~ "boolean()"
      assert String.contains?(result, "|")
    end

    test "maps union with two types" do
      python_type = %{
        "type" => "union",
        "types" => [
          %{"type" => "int"},
          %{"type" => "str"}
        ]
      }

      spec_ast = TypeMapper.to_spec(python_type)

      result = Macro.to_string(spec_ast)
      assert result == "integer() | String.t()" or result == "String.t() | integer()"
    end
  end

  describe "to_spec/1 with class types" do
    test "maps class to module reference" do
      python_type = %{
        "type" => "class",
        "name" => "MyClass"
      }

      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "MyClass.t()"
    end
  end

  describe "to_spec/1 with nested types" do
    test "maps list of lists" do
      python_type = %{
        "type" => "list",
        "element_type" => %{
          "type" => "list",
          "element_type" => %{"type" => "int"}
        }
      }

      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "list(list(integer()))"
    end

    test "maps dict with list values" do
      python_type = %{
        "type" => "dict",
        "key_type" => %{"type" => "str"},
        "value_type" => %{
          "type" => "list",
          "element_type" => %{"type" => "int"}
        }
      }

      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "%{optional(String.t()) => list(integer())}"
    end

    test "maps optional list" do
      python_type = %{
        "type" => "optional",
        "inner_type" => %{
          "type" => "list",
          "element_type" => %{"type" => "str"}
        }
      }

      spec_ast = TypeMapper.to_spec(python_type)

      result = Macro.to_string(spec_ast)
      assert result == "list(String.t()) | nil" or result == "nil | list(String.t())"
    end
  end

  describe "to_spec/1 with ML-specific types" do
    test "maps numpy.ndarray to Numpy.NDArray.t()" do
      python_type = %{"type" => "numpy.ndarray"}
      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "Numpy.NDArray.t()"
    end

    test "maps numpy.dtype to Numpy.DType.t()" do
      python_type = %{"type" => "numpy.dtype"}
      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "Numpy.DType.t()"
    end

    test "maps torch.tensor to Torch.Tensor.t()" do
      python_type = %{"type" => "torch.tensor"}
      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "Torch.Tensor.t()"
    end

    test "maps torch.Tensor (capitalized) to Torch.Tensor.t()" do
      python_type = %{"type" => "torch.Tensor"}
      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "Torch.Tensor.t()"
    end

    test "maps torch.dtype to Torch.DType.t()" do
      python_type = %{"type" => "torch.dtype"}
      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "Torch.DType.t()"
    end

    test "maps pandas.dataframe to Pandas.DataFrame.t()" do
      python_type = %{"type" => "pandas.dataframe"}
      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "Pandas.DataFrame.t()"
    end

    test "maps pandas.DataFrame (capitalized) to Pandas.DataFrame.t()" do
      python_type = %{"type" => "pandas.DataFrame"}
      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "Pandas.DataFrame.t()"
    end

    test "maps pandas.series to Pandas.Series.t()" do
      python_type = %{"type" => "pandas.series"}
      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "Pandas.Series.t()"
    end
  end

  describe "to_spec/1 edge cases" do
    test "handles missing element_type in list" do
      python_type = %{"type" => "list"}

      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "list(term())"
    end

    test "handles missing types in dict" do
      python_type = %{"type" => "dict"}

      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "%{optional(term()) => term()}"
    end

    test "handles unknown type" do
      python_type = %{"type" => "unknown_type"}

      spec_ast = TypeMapper.to_spec(python_type)

      assert Macro.to_string(spec_ast) == "term()"
    end

    test "handles nil input" do
      spec_ast = TypeMapper.to_spec(nil)

      assert Macro.to_string(spec_ast) == "term()"
    end

    test "handles empty map" do
      spec_ast = TypeMapper.to_spec(%{})

      assert Macro.to_string(spec_ast) == "term()"
    end
  end
end
