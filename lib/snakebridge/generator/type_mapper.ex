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
  def to_spec(nil), do: quote(do: term())
  def to_spec(%{} = python_type) when map_size(python_type) == 0, do: quote(do: term())

  # Primitive types
  def to_spec(%{"type" => "int"}), do: quote(do: integer())
  def to_spec(%{"type" => "float"}), do: quote(do: float())
  def to_spec(%{"type" => "str"}), do: quote(do: String.t())
  def to_spec(%{"type" => "string"}), do: quote(do: String.t())
  def to_spec(%{"type" => "bool"}), do: quote(do: boolean())
  def to_spec(%{"type" => "boolean"}), do: quote(do: boolean())
  def to_spec(%{"type" => "bytes"}), do: quote(do: binary())
  def to_spec(%{"type" => "bytearray"}), do: quote(do: binary())
  def to_spec(%{"type" => "none"}), do: quote(do: nil)
  def to_spec(%{"type" => "any"}), do: quote(do: term())

  # Complex types - delegate to specialized mappers
  def to_spec(%{"type" => "list"} = python_type), do: map_list_type(python_type)
  def to_spec(%{"type" => "dict"} = python_type), do: map_dict_type(python_type)
  def to_spec(%{"type" => "tuple"} = python_type), do: map_tuple_type(python_type)
  def to_spec(%{"type" => "set"} = python_type), do: map_set_type(python_type)
  def to_spec(%{"type" => "frozenset"} = python_type), do: map_set_type(python_type)
  def to_spec(%{"type" => "optional"} = python_type), do: map_optional_type(python_type)
  def to_spec(%{"type" => "union"} = python_type), do: map_union_type(python_type)
  def to_spec(%{"type" => "class"} = python_type), do: map_class_type(python_type)

  # ML-specific types (NumPy, PyTorch, Pandas)
  def to_spec(%{"type" => "numpy.ndarray"}), do: quote(do: Numpy.NDArray.t())
  def to_spec(%{"type" => "numpy.dtype"}), do: quote(do: Numpy.DType.t())
  def to_spec(%{"type" => "torch.tensor"}), do: quote(do: Torch.Tensor.t())
  def to_spec(%{"type" => "torch.Tensor"}), do: quote(do: Torch.Tensor.t())
  def to_spec(%{"type" => "torch.dtype"}), do: quote(do: Torch.DType.t())
  def to_spec(%{"type" => "pandas.dataframe"}), do: quote(do: Pandas.DataFrame.t())
  def to_spec(%{"type" => "pandas.DataFrame"}), do: quote(do: Pandas.DataFrame.t())
  def to_spec(%{"type" => "pandas.series"}), do: quote(do: Pandas.Series.t())
  def to_spec(%{"type" => "pandas.Series"}), do: quote(do: Pandas.Series.t())

  # Python integer alias
  def to_spec(%{"type" => "integer"}), do: quote(do: integer())

  # Fallback for unknown types
  def to_spec(%{"type" => _}), do: quote(do: term())
  def to_spec(_), do: quote(do: term())

  # Private Functions

  @spec map_list_type(map()) :: Macro.t()
  defp map_list_type(%{"element_type" => element_type}) do
    element_spec = to_spec(element_type)
    quote(do: list(unquote(element_spec)))
  end

  defp map_list_type(_), do: quote(do: list(term()))

  @spec map_dict_type(map()) :: Macro.t()
  defp map_dict_type(%{"key_type" => key_type, "value_type" => value_type}) do
    key_spec = to_spec(key_type)
    value_spec = to_spec(value_type)
    quote(do: %{optional(unquote(key_spec)) => unquote(value_spec)})
  end

  defp map_dict_type(_), do: quote(do: %{optional(term()) => term()})

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

  defp map_set_type(_), do: quote(do: MapSet.t(term()))

  @spec map_optional_type(map()) :: Macro.t()
  defp map_optional_type(%{"inner_type" => inner_type}) do
    inner_spec = to_spec(inner_type)
    quote(do: unquote(inner_spec) | nil)
  end

  defp map_optional_type(_), do: quote(do: term() | nil)

  @spec map_union_type(map()) :: Macro.t()
  defp map_union_type(%{"types" => types}) when is_list(types) and types != [] do
    type_specs = Enum.map(types, &to_spec/1)

    # Build union type using |
    Enum.reduce(type_specs, fn spec, acc ->
      quote(do: unquote(acc) | unquote(spec))
    end)
  end

  defp map_union_type(_), do: quote(do: term())

  @spec map_class_type(map()) :: Macro.t()
  defp map_class_type(%{"name" => name, "module" => module})
       when is_binary(name) and is_binary(module) do
    module_parts =
      module
      |> String.split(".")
      |> Enum.map(&Macro.camelize/1)
      |> Kernel.++([name])

    module_alias = {:__aliases__, [alias: false], Enum.map(module_parts, &String.to_atom/1)}

    {{:., [], [module_alias, :t]}, [], []}
  end

  defp map_class_type(%{"name" => name}) when is_binary(name) do
    module_alias = {:__aliases__, [alias: false], [String.to_atom(name)]}

    {{:., [], [module_alias, :t]}, [], []}
  end

  defp map_class_type(_), do: quote(do: term())
end
