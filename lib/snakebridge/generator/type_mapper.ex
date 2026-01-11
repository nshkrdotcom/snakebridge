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

  @context_key :snakebridge_type_mapper_context

  @type context :: %{
          class_map: %{{String.t(), String.t()} => String.t()},
          name_index: %{String.t() => MapSet.t(String.t())}
        }

  @spec build_context([map()]) :: context()
  def build_context(classes) when is_list(classes) do
    Enum.reduce(classes, default_context(), &accumulate_context/2)
  end

  defp accumulate_context(info, acc) do
    case class_context_entry(info) do
      {:ok, {python_module, class_name, module}} ->
        put_class_context(acc, python_module, class_name, module)

      :error ->
        acc
    end
  end

  defp class_context_entry(info) do
    python_module = info["python_module"] || info[:python_module]
    class_name = info["class"] || info["name"] || info[:class] || info[:name]
    module = info["module"] || info[:module]

    if is_binary(python_module) and is_binary(class_name) and is_binary(module) do
      {:ok, {python_module, class_name, module}}
    else
      :error
    end
  end

  defp put_class_context(acc, python_module, class_name, module) do
    acc
    |> put_in([:class_map, {python_module, class_name}], module)
    |> update_in([:name_index, class_name], fn set ->
      set = set || MapSet.new()
      MapSet.put(set, module)
    end)
  end

  @spec with_context(context(), (-> result)) :: result when result: var
  def with_context(context, fun) when is_function(fun, 0) do
    previous = Process.get(@context_key)
    Process.put(@context_key, context)

    try do
      fun.()
    after
      restore_context(previous)
    end
  end

  defp restore_context(nil), do: Process.delete(@context_key)
  defp restore_context(context), do: Process.put(@context_key, context)

  defp context do
    case Process.get(@context_key) do
      nil -> default_context()
      stored -> normalize_context(stored)
    end
  end

  defp default_context do
    %{class_map: %{}, name_index: %{}}
  end

  defp normalize_context(context) when is_map(context) do
    Map.merge(default_context(), context)
  end

  @doc """
  Converts a Python type dictionary to an Elixir typespec AST.

  ## Parameters

    * `python_type` - A map representing a Python type annotation

  ## Returns

  An AST node (quoted expression) representing the equivalent Elixir typespec.
  Class types resolve to generated modules only when a context is provided
  (via `to_spec/2` or `with_context/2`), otherwise they default to `term()`.

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
  def to_spec(python_type), do: to_spec(python_type, context())

  @spec to_spec(map() | nil, context()) :: Macro.t()
  def to_spec(nil, _context), do: quote(do: term())
  def to_spec(%{} = python_type, _context) when map_size(python_type) == 0, do: quote(do: term())

  # Primitive types
  def to_spec(%{"type" => "int"}, _context), do: quote(do: integer())
  def to_spec(%{"type" => "float"}, _context), do: quote(do: float())
  def to_spec(%{"type" => "str"}, _context), do: quote(do: String.t())
  def to_spec(%{"type" => "string"}, _context), do: quote(do: String.t())
  def to_spec(%{"type" => "bool"}, _context), do: quote(do: boolean())
  def to_spec(%{"type" => "boolean"}, _context), do: quote(do: boolean())
  def to_spec(%{"type" => "bytes"}, _context), do: quote(do: binary())
  def to_spec(%{"type" => "bytearray"}, _context), do: quote(do: binary())
  def to_spec(%{"type" => "none"}, _context), do: quote(do: nil)
  def to_spec(%{"type" => "any"}, _context), do: quote(do: term())

  # Complex types - delegate to specialized mappers
  def to_spec(%{"type" => "list"} = python_type, context), do: map_list_type(python_type, context)
  def to_spec(%{"type" => "dict"} = python_type, context), do: map_dict_type(python_type, context)

  def to_spec(%{"type" => "tuple"} = python_type, context),
    do: map_tuple_type(python_type, context)

  def to_spec(%{"type" => "set"} = python_type, context), do: map_set_type(python_type, context)

  def to_spec(%{"type" => "frozenset"} = python_type, context),
    do: map_set_type(python_type, context)

  def to_spec(%{"type" => "optional"} = python_type, context),
    do: map_optional_type(python_type, context)

  def to_spec(%{"type" => "union"} = python_type, context),
    do: map_union_type(python_type, context)

  def to_spec(%{"type" => "class"} = python_type, context),
    do: map_class_type(python_type, context)

  def to_spec(%{"type" => type} = python_type, context) when is_binary(type) do
    if String.contains?(type, ".") do
      map_qualified_type(python_type, context)
    else
      # Python integer alias or unknown types
      if type == "integer" do
        quote(do: integer())
      else
        quote(do: term())
      end
    end
  end

  # Fallback for unknown types
  def to_spec(_python_type, _context), do: quote(do: term())

  # Private Functions

  @spec map_list_type(map(), context()) :: Macro.t()
  defp map_list_type(%{"element_type" => element_type}, context) do
    element_spec = to_spec(element_type, context)
    quote(do: list(unquote(element_spec)))
  end

  defp map_list_type(_python_type, _context), do: quote(do: list(term()))

  @spec map_dict_type(map(), context()) :: Macro.t()
  defp map_dict_type(%{"key_type" => key_type, "value_type" => value_type}, context) do
    key_spec = to_spec(key_type, context)
    value_spec = to_spec(value_type, context)
    quote(do: %{optional(unquote(key_spec)) => unquote(value_spec)})
  end

  defp map_dict_type(_python_type, _context), do: quote(do: %{optional(term()) => term()})

  @spec map_tuple_type(map(), context()) :: Macro.t()
  defp map_tuple_type(%{"element_types" => element_types}, context)
       when is_list(element_types) do
    case element_types do
      [] ->
        {:{}, [], []}

      types ->
        element_specs = Enum.map(types, &to_spec(&1, context))
        {:{}, [], element_specs}
    end
  end

  defp map_tuple_type(_python_type, _context), do: quote(do: tuple())

  @spec map_set_type(map(), context()) :: Macro.t()
  defp map_set_type(%{"element_type" => element_type}, context) do
    element_spec = to_spec(element_type, context)
    quote(do: MapSet.t(unquote(element_spec)))
  end

  defp map_set_type(_python_type, _context), do: quote(do: MapSet.t(term()))

  @spec map_optional_type(map(), context()) :: Macro.t()
  defp map_optional_type(%{"inner_type" => inner_type}, context) do
    inner_spec = to_spec(inner_type, context)
    quote(do: unquote(inner_spec) | nil)
  end

  defp map_optional_type(_python_type, _context), do: quote(do: term() | nil)

  @spec map_union_type(map(), context()) :: Macro.t()
  defp map_union_type(%{"types" => types}, context) when is_list(types) and types != [] do
    type_specs = Enum.map(types, &to_spec(&1, context))

    # Build union type using |
    Enum.reduce(type_specs, fn spec, acc ->
      quote(do: unquote(acc) | unquote(spec))
    end)
  end

  defp map_union_type(_python_type, _context), do: quote(do: term())

  @spec map_class_type(map(), context()) :: Macro.t()
  defp map_class_type(python_type, context) do
    case resolve_class_module(python_type, context) do
      module when is_binary(module) -> module_type_ast(module)
      _ -> quote(do: term())
    end
  end

  defp map_qualified_type(%{"type" => type} = python_type, context) when is_binary(type) do
    resolved =
      python_type
      |> Map.put_new("module", module_from_qualified(type))
      |> Map.put_new("name", name_from_qualified(type))
      |> resolve_class_module(context)

    case resolved do
      module when is_binary(module) -> module_type_ast(module)
      _ -> quote(do: term())
    end
  end

  defp resolve_class_module(%{"module" => module, "name" => name}, context)
       when is_binary(module) and is_binary(name) do
    context
    |> Map.get(:class_map, %{})
    |> Map.get({module, name})
  end

  defp resolve_class_module(%{"name" => name}, context) when is_binary(name) do
    case context |> Map.get(:name_index, %{}) |> Map.get(name) do
      %MapSet{} = modules ->
        case MapSet.to_list(modules) do
          [module] -> module
          _ -> nil
        end

      modules when is_list(modules) ->
        case Enum.uniq(modules) do
          [module] -> module
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp resolve_class_module(_python_type, _context), do: nil

  defp module_type_ast(module) do
    module_alias =
      module
      |> String.split(".")
      |> Enum.map(&String.to_atom/1)
      |> then(&{:__aliases__, [alias: false], &1})

    {{:., [], [module_alias, :t]}, [], []}
  end

  defp module_from_qualified(type) do
    type
    |> String.split(".")
    |> Enum.drop(-1)
    |> Enum.join(".")
  end

  defp name_from_qualified(type) do
    type
    |> String.split(".")
    |> List.last()
  end
end
