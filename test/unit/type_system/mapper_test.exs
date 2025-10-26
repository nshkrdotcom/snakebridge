defmodule SnakeBridge.TypeSystem.MapperTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.TypeSystem.Mapper
  alias SnakeBridge.TestFixtures

  describe "to_elixir_spec/1" do
    test "maps primitive types" do
      types = TestFixtures.sample_type_descriptors()

      assert Mapper.to_elixir_spec(types.int) == quote(do: integer())
      assert Mapper.to_elixir_spec(types.str) == quote(do: String.t())
      assert Mapper.to_elixir_spec(types.float) == quote(do: float())
      assert Mapper.to_elixir_spec(types.bool) == quote(do: boolean())
    end

    test "maps list types" do
      types = TestFixtures.sample_type_descriptors()

      spec = Mapper.to_elixir_spec(types.list_int)

      assert Macro.to_string(spec) == "[integer()]"
    end

    test "maps dict types to maps" do
      types = TestFixtures.sample_type_descriptors()

      spec = Mapper.to_elixir_spec(types.dict_str_any)

      # %{optional(String.t()) => term()}
      assert is_tuple(spec)
    end

    test "maps union types" do
      types = TestFixtures.sample_type_descriptors()

      spec = Mapper.to_elixir_spec(types.union_int_str)

      spec_string = Macro.to_string(spec)
      assert String.contains?(spec_string, "integer()")
      assert String.contains?(spec_string, "String.t()")
      assert String.contains?(spec_string, "|")
    end

    test "maps optional types" do
      types = TestFixtures.sample_type_descriptors()

      spec = Mapper.to_elixir_spec(types.optional_str)

      spec_string = Macro.to_string(spec)
      assert String.contains?(spec_string, "String.t()")
      assert String.contains?(spec_string, "nil")
    end

    test "maps class types to opaque module types" do
      class_type = %{kind: "class", class_path: "dspy.Predict"}

      spec = Mapper.to_elixir_spec(class_type)

      # Should generate DSPy.Predict.t()
      assert is_tuple(spec)
    end
  end

  describe "infer_python_type/1" do
    test "infers types from Elixir values" do
      assert Mapper.infer_python_type(42) == :int
      assert Mapper.infer_python_type(3.14) == :float
      assert Mapper.infer_python_type("hello") == :str
      assert Mapper.infer_python_type(true) == :bool
      assert Mapper.infer_python_type(false) == :bool
      assert Mapper.infer_python_type(nil) == :none
    end

    test "infers list types" do
      assert Mapper.infer_python_type([1, 2, 3]) == {:list, :int}
      assert Mapper.infer_python_type(["a", "b"]) == {:list, :str}
      assert Mapper.infer_python_type([]) == {:list, :any}
    end

    test "infers dict types" do
      assert Mapper.infer_python_type(%{"key" => 1}) == {:dict, :str, :int}
      assert Mapper.infer_python_type(%{key: "value"}) == {:dict, :str, :str}
      assert Mapper.infer_python_type(%{}) == {:dict, :str, :any}
    end
  end

  describe "python_class_to_elixir_module/1" do
    test "converts Python class path to Elixir module" do
      assert Mapper.python_class_to_elixir_module("dspy.Predict") == DSPy.Predict

      assert Mapper.python_class_to_elixir_module("langchain.chains.LLMChain") ==
               Langchain.Chains.LLMChain
    end

    test "handles single-level modules" do
      assert Mapper.python_class_to_elixir_module("requests") == Requests
    end
  end

  describe "type conversion roundtrip" do
    test "can convert Elixir value to Python and back" do
      value = %{"question" => "What is Elixir?", "temperature" => 0.7}

      python_type = Mapper.infer_python_type(value)
      elixir_spec = Mapper.to_elixir_spec(python_type)

      # Mixed value types
      assert python_type == {:dict, :str, :any}
      assert is_tuple(elixir_spec)
    end
  end
end
