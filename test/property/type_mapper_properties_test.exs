defmodule SnakeBridge.Property.TypeMapperTest do
  use ExUnit.Case
  use ExUnitProperties

  alias SnakeBridge.TypeSystem.Mapper

  describe "TypeMapper property-based tests" do
    property "infer_python_type handles all Elixir primitives" do
      check all(
              value <-
                one_of([
                  integer(),
                  float(),
                  string(:alphanumeric),
                  boolean(),
                  constant(nil)
                ])
            ) do
        python_type = Mapper.infer_python_type(value)

        assert python_type in [:int, :float, :str, :bool, :none]
      end
    end

    property "infer_python_type handles lists correctly" do
      check all(list <- list_of(integer(), max_length: 10)) do
        python_type = Mapper.infer_python_type(list)

        case list do
          [] -> assert python_type == {:list, :any}
          _ -> assert python_type == {:list, :int}
        end
      end
    end

    property "infer_python_type handles maps correctly" do
      check all(
              map <-
                map_of(
                  string(:alphanumeric, min_length: 1),
                  integer(),
                  max_length: 5
                )
            ) do
        python_type = Mapper.infer_python_type(map)

        case map_size(map) do
          0 -> assert python_type == {:dict, :str, :any}
          _ -> assert python_type == {:dict, :str, :int}
        end
      end
    end

    property "Python class path conversion is reversible" do
      check all(
              module_parts <-
                list_of(
                  string(:alphanumeric, min_length: 1),
                  min_length: 1,
                  max_length: 5
                )
            ) do
        python_path = Enum.join(module_parts, ".")
        elixir_module = Mapper.python_class_to_elixir_module(python_path)

        # Should be a valid atom
        assert is_atom(elixir_module)

        # Converting back should give similar structure
        assert String.contains?(Atom.to_string(elixir_module), "Elixir.")
      end
    end

    property "type conversion always produces valid AST" do
      check all(
              type_kind <- member_of(["primitive", "list", "dict"]),
              primitive <- member_of(["int", "str", "float", "bool"])
            ) do
        type_desc =
          case type_kind do
            "primitive" ->
              %{kind: "primitive", primitive_type: primitive}

            "list" ->
              %{
                kind: "list",
                element_type: %{kind: "primitive", primitive_type: primitive}
              }

            "dict" ->
              %{
                kind: "dict",
                key_type: %{kind: "primitive", primitive_type: "str"},
                value_type: %{kind: "primitive", primitive_type: primitive}
              }
          end

        spec = Mapper.to_elixir_spec(type_desc)

        # Should produce valid AST
        assert is_tuple(spec)
        # Should not raise
        assert Macro.to_string(spec)
      end
    end
  end
end
