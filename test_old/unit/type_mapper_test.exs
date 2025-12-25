defmodule SnakeBridge.TypeSystem.MapperTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.TypeSystem.Mapper

  describe "normalize_descriptor/1" do
    test "normalizes string-keyed descriptors with type key" do
      descriptor = %{"type" => "int"}
      normalized = Mapper.normalize_descriptor(descriptor)

      assert normalized.kind == "primitive"
      assert normalized.primitive_type == "int"
    end

    test "normalizes string-keyed descriptors with kind/primitive_type" do
      descriptor = %{"kind" => "primitive", "primitive_type" => "str"}
      normalized = Mapper.normalize_descriptor(descriptor)

      assert normalized.kind == "primitive"
      assert normalized.primitive_type == "str"
    end

    test "normalizes atom-keyed descriptors" do
      descriptor = %{kind: "primitive", primitive_type: "float"}
      normalized = Mapper.normalize_descriptor(descriptor)

      assert normalized.kind == "primitive"
      assert normalized.primitive_type == "float"
    end

    test "normalizes list type" do
      descriptor = %{"type" => "list", "element_type" => %{"type" => "int"}}
      normalized = Mapper.normalize_descriptor(descriptor)

      assert normalized.kind == "list"
      assert normalized.element_type.kind == "primitive"
      assert normalized.element_type.primitive_type == "int"
    end

    test "normalizes dict type" do
      descriptor = %{
        "type" => "dict",
        "key_type" => %{"type" => "str"},
        "value_type" => %{"type" => "any"}
      }

      normalized = Mapper.normalize_descriptor(descriptor)

      assert normalized.kind == "dict"
      assert normalized.key_type.kind == "primitive"
      assert normalized.value_type.kind == "primitive"
    end

    test "normalizes ndarray type to class" do
      descriptor = %{"type" => "ndarray", "dtype" => "float64"}
      normalized = Mapper.normalize_descriptor(descriptor)

      # Library-specific types now fall through to class_or_any
      assert normalized.kind == "primitive"
      assert normalized.primitive_type == "any"
    end

    test "normalizes DataFrame type to class" do
      descriptor = %{"type" => "DataFrame"}
      normalized = Mapper.normalize_descriptor(descriptor)

      # Library-specific types now fall through to class_or_any
      assert normalized.kind == "class"
      assert normalized.class_path == "DataFrame"
    end

    test "normalizes Tensor type to class" do
      descriptor = %{"type" => "Tensor", "dtype" => "float32"}
      normalized = Mapper.normalize_descriptor(descriptor)

      # Library-specific types now fall through to class_or_any
      assert normalized.kind == "class"
      assert normalized.class_path == "Tensor"
    end
  end

  describe "to_elixir_spec/1 with primitives" do
    test "converts int" do
      spec = Mapper.to_elixir_spec(%{kind: "primitive", primitive_type: "int"})
      assert Macro.to_string(spec) == "integer()"
    end

    test "converts str" do
      spec = Mapper.to_elixir_spec(%{kind: "primitive", primitive_type: "str"})
      assert Macro.to_string(spec) == "String.t()"
    end

    test "converts float" do
      spec = Mapper.to_elixir_spec(%{kind: "primitive", primitive_type: "float"})
      assert Macro.to_string(spec) == "float()"
    end

    test "converts bool" do
      spec = Mapper.to_elixir_spec(%{kind: "primitive", primitive_type: "bool"})
      assert Macro.to_string(spec) == "boolean()"
    end

    test "converts bytes" do
      spec = Mapper.to_elixir_spec(%{kind: "primitive", primitive_type: "bytes"})
      assert Macro.to_string(spec) == "binary()"
    end

    test "converts none" do
      spec = Mapper.to_elixir_spec(%{kind: "primitive", primitive_type: "none"})
      assert Macro.to_string(spec) == "nil"
    end

    test "converts any" do
      spec = Mapper.to_elixir_spec(%{kind: "primitive", primitive_type: "any"})
      assert Macro.to_string(spec) == "term()"
    end
  end

  describe "to_elixir_spec/1 with collections" do
    test "converts list type" do
      spec =
        Mapper.to_elixir_spec(%{
          kind: "list",
          element_type: %{kind: "primitive", primitive_type: "int"}
        })

      assert Macro.to_string(spec) == "[integer()]"
    end

    test "converts dict type" do
      spec =
        Mapper.to_elixir_spec(%{
          kind: "dict",
          key_type: %{kind: "primitive", primitive_type: "str"},
          value_type: %{kind: "primitive", primitive_type: "any"}
        })

      assert Macro.to_string(spec) == "%{optional(String.t()) => term()}"
    end

    test "converts tuple type" do
      spec =
        Mapper.to_elixir_spec(%{
          kind: "tuple",
          element_types: [
            %{kind: "primitive", primitive_type: "int"},
            %{kind: "primitive", primitive_type: "str"}
          ]
        })

      assert Macro.to_string(spec) == "{integer(), String.t()}"
    end

    test "converts set type" do
      spec =
        Mapper.to_elixir_spec(%{
          kind: "set",
          element_type: %{kind: "primitive", primitive_type: "str"}
        })

      assert Macro.to_string(spec) == "MapSet.t(String.t())"
    end
  end

  describe "to_elixir_spec/1 with union types" do
    test "converts union type" do
      spec =
        Mapper.to_elixir_spec(%{
          kind: "union",
          union_types: [
            %{kind: "primitive", primitive_type: "int"},
            %{kind: "primitive", primitive_type: "str"}
          ]
        })

      assert Macro.to_string(spec) == "integer() | String.t()"
    end

    test "converts optional type (union with none)" do
      spec =
        Mapper.to_elixir_spec(%{
          kind: "union",
          union_types: [
            %{kind: "primitive", primitive_type: "str"},
            %{kind: "primitive", primitive_type: "none"}
          ]
        })

      assert Macro.to_string(spec) == "String.t() | nil"
    end
  end

  describe "to_elixir_spec/1 with unknown library types" do
    test "converts ndarray to term() (fallback)" do
      spec = Mapper.to_elixir_spec(%{kind: "ndarray"})
      assert Macro.to_string(spec) == "term()"
    end

    test "converts ndarray with dtype to term() (fallback)" do
      spec = Mapper.to_elixir_spec(%{kind: "ndarray", dtype: "float64"})
      assert Macro.to_string(spec) == "term()"
    end

    test "converts dataframe to term() (fallback)" do
      spec = Mapper.to_elixir_spec(%{kind: "dataframe"})
      assert Macro.to_string(spec) == "term()"
    end

    test "converts tensor to term() (fallback)" do
      spec = Mapper.to_elixir_spec(%{kind: "tensor"})
      assert Macro.to_string(spec) == "term()"
    end

    test "converts series to term() (fallback)" do
      spec = Mapper.to_elixir_spec(%{kind: "series"})
      assert Macro.to_string(spec) == "term()"
    end
  end

  describe "to_elixir_spec/1 with datetime types" do
    test "converts datetime" do
      spec = Mapper.to_elixir_spec(%{kind: "datetime"})
      assert Macro.to_string(spec) == "DateTime.t()"
    end

    test "converts date" do
      spec = Mapper.to_elixir_spec(%{kind: "date"})
      assert Macro.to_string(spec) == "Date.t()"
    end

    test "converts time" do
      spec = Mapper.to_elixir_spec(%{kind: "time"})
      assert Macro.to_string(spec) == "Time.t()"
    end

    test "converts timedelta" do
      spec = Mapper.to_elixir_spec(%{kind: "timedelta"})
      assert Macro.to_string(spec) == "integer()"
    end
  end

  describe "to_elixir_spec/1 with class types" do
    test "converts class to module.t()" do
      spec = Mapper.to_elixir_spec(%{kind: "class", class_path: "demo.Predict"})
      assert Macro.to_string(spec) == "Demo.Predict.t()"
    end
  end

  describe "to_elixir_spec/1 with callable types" do
    test "converts callable" do
      spec = Mapper.to_elixir_spec(%{kind: "callable"})
      assert Macro.to_string(spec) == "(... -> term())"
    end
  end

  describe "to_elixir_spec/1 with generator types" do
    test "converts generator to Enumerable.t()" do
      spec = Mapper.to_elixir_spec(%{kind: "generator"})
      assert Macro.to_string(spec) == "Enumerable.t()"
    end

    test "converts async_generator to Enumerable.t()" do
      spec = Mapper.to_elixir_spec(%{kind: "async_generator"})
      assert Macro.to_string(spec) == "Enumerable.t()"
    end
  end

  describe "to_elixir_spec/1 with fallback" do
    test "returns term() for unknown types" do
      spec = Mapper.to_elixir_spec(%{kind: "unknown_type"})
      assert Macro.to_string(spec) == "term()"
    end

    test "returns term() for nil" do
      spec = Mapper.to_elixir_spec(nil)
      assert Macro.to_string(spec) == "term()"
    end
  end

  describe "infer_python_type/1" do
    test "infers int from integer" do
      assert Mapper.infer_python_type(42) == :int
    end

    test "infers float from float" do
      assert Mapper.infer_python_type(3.14) == :float
    end

    test "infers str from string" do
      assert Mapper.infer_python_type("hello") == :str
    end

    test "infers bool from boolean" do
      assert Mapper.infer_python_type(true) == :bool
    end

    test "infers none from nil" do
      assert Mapper.infer_python_type(nil) == :none
    end

    test "infers list type from list" do
      assert Mapper.infer_python_type([1, 2, 3]) == {:list, :int}
    end

    test "infers dict type from map" do
      assert Mapper.infer_python_type(%{"a" => 1}) == {:dict, :str, :int}
    end
  end

  describe "python_class_to_elixir_module/1" do
    test "converts simple path" do
      assert Mapper.python_class_to_elixir_module("json") == Json
    end

    test "converts dotted path" do
      assert Mapper.python_class_to_elixir_module("demo.Predict") == Demo.Predict
    end

    test "preserves acronyms like AI, ML" do
      assert Mapper.python_class_to_elixir_module("ai.Module") == AI.Module
      assert Mapper.python_class_to_elixir_module("ml.Module") == ML.Module
    end
  end
end
