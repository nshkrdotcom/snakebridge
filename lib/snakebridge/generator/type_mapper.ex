defmodule SnakeBridge.Generator.TypeMapper do
  @moduledoc """
  Maps Python type annotations to Elixir typespec AST.

  This module converts Python type dictionaries (as produced by the introspection
  script) into Elixir typespec AST using `quote`. The AST can then be used to
  generate `@spec` declarations in generated modules.

  ## Type Mappings

  | Python Type | Elixir Type |
  |------------|-------------|
  | `int` | `integer()` |
  | `float` | `float()` |
  | `str` | `String.t()` |
  | `bool` | `boolean()` |
  | `bytes` | `binary()` |
  | `None` | `nil` |
  | `list[T]` | `list(T)` |
  | `dict[K, V]` | `map(K, V)` |
  | `tuple[T1, T2, ...]` | `{T1, T2, ...}` |
  | `set[T]` | `MapSet.t(T)` |
  | `Optional[T]` | `T \\| nil` |
  | `Union[T1, T2, ...]` | `T1 \\| T2 \\| ...` |
  | `ClassName` | `ClassName.t()` |
  | `Any` | `any()` |

  ## Examples

      iex> TypeMapper.to_spec(%{"type" => "int"})
      {:integer, [], []}

      iex> TypeMapper.to_spec(%{"type" => "list", "element_type" => %{"type" => "str"}})
      {{:., [], [{:__aliases__, [alias: false], [:String]}, :t]}, [], []}
      |> Macro.to_string()
      "list(String.t())"

  """

  @doc """
  Converts a Python type dictionary to an Elixir typespec AST.

  ## Parameters

    * `python_type` - A map representing a Python type annotation

  ## Returns

  An AST node (quoted expression) representing the equivalent Elixir typespec.

  ## Examples

      iex> python_type = %{"type" => "int"}
      iex> ast = SnakeBridge.Generator.TypeMapper.to_spec(python_type)
      iex> Macro.to_string(ast)
      "integer()"

      iex> python_type = %{"type" => "list", "element_type" => %{"type" => "int"}}
      iex> ast = SnakeBridge.Generator.TypeMapper.to_spec(python_type)
      iex> Macro.to_string(ast)
      "list(integer())"

  """
  @spec to_spec(map() | nil) :: Macro.t()
  def to_spec(nil), do: quote(do: any())
  def to_spec(%{} = python_type) when map_size(python_type) == 0, do: quote(do: any())

  def to_spec(%{"type" => type} = python_type) do
    case type do
      "int" -> quote(do: integer())
      "float" -> quote(do: float())
      "str" -> quote(do: String.t())
      "bool" -> quote(do: boolean())
      "bytes" -> quote(do: binary())
      "none" -> quote(do: nil)
      "any" -> quote(do: any())
      "list" -> map_list_type(python_type)
      "dict" -> map_dict_type(python_type)
      "tuple" -> map_tuple_type(python_type)
      "set" -> map_set_type(python_type)
      "optional" -> map_optional_type(python_type)
      "union" -> map_union_type(python_type)
      "class" -> map_class_type(python_type)
      _ -> quote(do: any())
    end
  end

  def to_spec(_), do: quote(do: any())

  # Private Functions

  @spec map_list_type(map()) :: Macro.t()
  defp map_list_type(%{"element_type" => element_type}) do
    element_spec = to_spec(element_type)
    quote(do: list(unquote(element_spec)))
  end

  defp map_list_type(_), do: quote(do: list(any()))

  @spec map_dict_type(map()) :: Macro.t()
  defp map_dict_type(%{"key_type" => key_type, "value_type" => value_type}) do
    key_spec = to_spec(key_type)
    value_spec = to_spec(value_type)
    quote(do: map(unquote(key_spec), unquote(value_spec)))
  end

  defp map_dict_type(_), do: quote(do: map(any(), any()))

  @spec map_tuple_type(map()) :: Macro.t()
  defp map_tuple_type(%{"element_types" => element_types}) when is_list(element_types) do
    case element_types do
      [] ->
        {:{}, [], []}

      types ->
        element_specs = Enum.map(types, &to_spec/1)
        {:{}, [], element_specs}
    end
  end

  defp map_tuple_type(_), do: quote(do: tuple())

  @spec map_set_type(map()) :: Macro.t()
  defp map_set_type(%{"element_type" => element_type}) do
    element_spec = to_spec(element_type)
    quote(do: MapSet.t(unquote(element_spec)))
  end

  defp map_set_type(_), do: quote(do: MapSet.t(any()))

  @spec map_optional_type(map()) :: Macro.t()
  defp map_optional_type(%{"inner_type" => inner_type}) do
    inner_spec = to_spec(inner_type)
    quote(do: unquote(inner_spec) | nil)
  end

  defp map_optional_type(_), do: quote(do: any() | nil)

  @spec map_union_type(map()) :: Macro.t()
  defp map_union_type(%{"types" => types}) when is_list(types) and length(types) > 0 do
    type_specs = Enum.map(types, &to_spec/1)

    # Build union type using |
    Enum.reduce(type_specs, fn spec, acc ->
      quote(do: unquote(acc) | unquote(spec))
    end)
  end

  defp map_union_type(_), do: quote(do: any())

  @spec map_class_type(map()) :: Macro.t()
  defp map_class_type(%{"name" => name}) when is_binary(name) do
    # Convert class name to module alias and add .t()
    module_alias = {:__aliases__, [alias: false], [String.to_atom(name)]}

    {{:., [], [module_alias, :t]}, [], []}
  end

  defp map_class_type(_), do: quote(do: any())
end
