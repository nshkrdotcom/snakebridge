defmodule SnakeBridge.TypeSystem.Mapper do
  @moduledoc """
  Maps between Python type system and Elixir typespecs.

  Supports ~15 concrete types plus normalization of descriptor formats
  to handle both `kind/primitive_type` and `type` style keys.

  ## Supported Types

  ### Primitives
  - int -> integer()
  - str -> String.t()
  - float -> float()
  - bool -> boolean()
  - bytes -> binary()
  - none -> nil
  - any -> term()

  ### Collections
  - list -> [element_type()]
  - dict -> %{optional(key_type) => value_type}
  - tuple -> {type1, type2, ...}
  - set -> MapSet.t(element_type)

  ### NumPy/ML Types
  - ndarray -> list(number()) with dtype consideration
  - DataFrame -> list(map())
  - Tensor -> list(number())
  - Series -> list(term())

  ### Datetime Types
  - datetime -> DateTime.t()
  - date -> Date.t()
  - time -> Time.t()
  - timedelta -> integer()

  ### Callable/Generator Types
  - callable -> (... -> term())
  - generator -> Enumerable.t()
  - async_generator -> Enumerable.t()

  ### Union Types
  - union -> type1 | type2
  """

  @doc """
  Normalize a Python type descriptor to a consistent atom-keyed map format.

  Handles both:
  - `%{"type" => "int"}` style
  - `%{"kind" => "primitive", "primitive_type" => "int"}` style
  - `%{kind: "primitive", primitive_type: "int"}` style

  ## Examples

      iex> Mapper.normalize_descriptor(%{"type" => "int"})
      %{kind: "primitive", primitive_type: "int"}

      iex> Mapper.normalize_descriptor(%{"kind" => "list", "element_type" => %{"type" => "str"}})
      %{kind: "list", element_type: %{kind: "primitive", primitive_type: "str"}}
  """
  @known_keys ~w(type kind primitive_type element_type key_type value_type element_types union_types class_path dtype)

  @spec normalize_descriptor(map() | String.t() | nil) :: map() | nil
  def normalize_descriptor(nil), do: nil

  def normalize_descriptor(type) when is_binary(type) do
    normalize_descriptor(%{"type" => type})
  end

  def normalize_descriptor(descriptor) when is_map(descriptor) do
    # First, convert all keys to atoms for consistency
    normalized = atomize_keys(descriptor)

    # Handle "type" style descriptors
    case normalized do
      %{type: type_str} when is_binary(type_str) ->
        normalize_type_string(type_str, normalized)

      %{kind: kind} ->
        normalize_by_kind(kind, normalized)

      _ ->
        %{kind: "primitive", primitive_type: "any"}
    end
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) and k in @known_keys ->
        {String.to_atom(k), atomize_value(v)}

      {k, v} when is_atom(k) ->
        key_string = Atom.to_string(k)

        if key_string in @known_keys do
          {k, atomize_value(v)}
        else
          {key_string, atomize_value(v)}
        end

      {k, v} ->
        {k, atomize_value(v)}
    end)
  end

  defp atomize_value(v) when is_map(v), do: atomize_keys(v)
  defp atomize_value(v) when is_list(v), do: Enum.map(v, &atomize_value/1)
  defp atomize_value(v), do: v

  defp normalize_type_string(type_str, original) do
    cond do
      normalize_primitive_type(type_str) ->
        normalize_primitive_type(type_str)

      normalize_collection_type(type_str, original) ->
        normalize_collection_type(type_str, original)

      normalize_numpy_ml_type(type_str, original) ->
        normalize_numpy_ml_type(type_str, original)

      normalize_datetime_type(type_str) ->
        normalize_datetime_type(type_str)

      normalize_callable_type(type_str) ->
        normalize_callable_type(type_str)

      normalize_union_type(type_str, original) ->
        normalize_union_type(type_str, original)

      true ->
        normalize_class_or_any(type_str)
    end
  end

  defp normalize_primitive_type(type_str) do
    case type_str do
      t when t in ["int", "integer"] -> %{kind: "primitive", primitive_type: "int"}
      t when t in ["str", "string"] -> %{kind: "primitive", primitive_type: "str"}
      "float" -> %{kind: "primitive", primitive_type: "float"}
      t when t in ["bool", "boolean"] -> %{kind: "primitive", primitive_type: "bool"}
      "bytes" -> %{kind: "primitive", primitive_type: "bytes"}
      t when t in ["none", "None", "NoneType"] -> %{kind: "primitive", primitive_type: "none"}
      "any" -> %{kind: "primitive", primitive_type: "any"}
      _ -> nil
    end
  end

  defp normalize_collection_type(type_str, original) do
    case type_str do
      "list" ->
        element = Map.get(original, :element_type)
        %{kind: "list", element_type: normalize_descriptor(element)}

      "dict" ->
        key = Map.get(original, :key_type)
        value = Map.get(original, :value_type)

        %{
          kind: "dict",
          key_type: normalize_descriptor(key),
          value_type: normalize_descriptor(value)
        }

      "tuple" ->
        elements = Map.get(original, :element_types, [])
        %{kind: "tuple", element_types: Enum.map(elements, &normalize_descriptor/1)}

      "set" ->
        element = Map.get(original, :element_type)
        %{kind: "set", element_type: normalize_descriptor(element)}

      _ ->
        nil
    end
  end

  defp normalize_numpy_ml_type(type_str, original) do
    case type_str do
      "ndarray" -> %{kind: "ndarray", dtype: Map.get(original, :dtype)}
      "DataFrame" -> %{kind: "dataframe"}
      "Tensor" -> %{kind: "tensor", dtype: Map.get(original, :dtype)}
      "Series" -> %{kind: "series"}
      _ -> nil
    end
  end

  defp normalize_datetime_type(type_str) do
    case type_str do
      "datetime" -> %{kind: "datetime"}
      "date" -> %{kind: "date"}
      "time" -> %{kind: "time"}
      "timedelta" -> %{kind: "timedelta"}
      _ -> nil
    end
  end

  defp normalize_callable_type(type_str) do
    case type_str do
      "callable" -> %{kind: "callable"}
      "generator" -> %{kind: "generator"}
      "async_generator" -> %{kind: "async_generator"}
      _ -> nil
    end
  end

  defp normalize_union_type(type_str, original) do
    case type_str do
      "union" ->
        types = Map.get(original, :union_types, [])
        %{kind: "union", union_types: Enum.map(types, &normalize_descriptor/1)}

      _ ->
        nil
    end
  end

  defp normalize_class_or_any(type_str) do
    if String.contains?(type_str, ".") or String.match?(type_str, ~r/^[A-Z]/) do
      %{kind: "class", class_path: type_str}
    else
      %{kind: "primitive", primitive_type: "any"}
    end
  end

  defp normalize_by_kind(kind, original) do
    normalize_by_kind_primitive(kind, original) ||
      normalize_by_kind_collection(kind, original) ||
      normalize_by_kind_numpy_ml(kind, original) ||
      normalize_by_kind_datetime(kind) ||
      normalize_by_kind_callable(kind) ||
      %{kind: "primitive", primitive_type: "any"}
  end

  defp normalize_by_kind_primitive(kind, original) do
    case kind do
      "primitive" ->
        %{kind: "primitive", primitive_type: Map.get(original, :primitive_type, "any")}

      _ ->
        nil
    end
  end

  defp normalize_by_kind_collection(kind, original) do
    case kind do
      "list" ->
        %{kind: "list", element_type: normalize_descriptor(Map.get(original, :element_type))}

      "dict" ->
        %{
          kind: "dict",
          key_type: normalize_descriptor(Map.get(original, :key_type)),
          value_type: normalize_descriptor(Map.get(original, :value_type))
        }

      "tuple" ->
        %{
          kind: "tuple",
          element_types: Enum.map(Map.get(original, :element_types, []), &normalize_descriptor/1)
        }

      "set" ->
        %{kind: "set", element_type: normalize_descriptor(Map.get(original, :element_type))}

      "union" ->
        %{
          kind: "union",
          union_types: Enum.map(Map.get(original, :union_types, []), &normalize_descriptor/1)
        }

      "class" ->
        %{kind: "class", class_path: Map.get(original, :class_path, "object")}

      _ ->
        nil
    end
  end

  defp normalize_by_kind_numpy_ml(kind, original) do
    case kind do
      "ndarray" -> %{kind: "ndarray", dtype: Map.get(original, :dtype)}
      "dataframe" -> %{kind: "dataframe"}
      "tensor" -> %{kind: "tensor", dtype: Map.get(original, :dtype)}
      "series" -> %{kind: "series"}
      _ -> nil
    end
  end

  defp normalize_by_kind_datetime(kind) do
    case kind do
      "datetime" -> %{kind: "datetime"}
      "date" -> %{kind: "date"}
      "time" -> %{kind: "time"}
      "timedelta" -> %{kind: "timedelta"}
      _ -> nil
    end
  end

  defp normalize_by_kind_callable(kind) do
    case kind do
      "callable" -> %{kind: "callable"}
      "generator" -> %{kind: "generator"}
      "async_generator" -> %{kind: "async_generator"}
      _ -> nil
    end
  end

  @doc """
  Convert Python type descriptor to Elixir typespec AST.

  Accepts both normalized and non-normalized descriptors. Non-normalized
  descriptors are automatically normalized first.

  ## Examples

      iex> Mapper.to_elixir_spec(%{kind: "primitive", primitive_type: "int"})
      {:integer, [], []}

      iex> Mapper.to_elixir_spec(%{"type" => "str"})
      {{:., [], [{:__aliases__, [alias: false], [:String]}, :t]}, [], []}
  """
  @spec to_elixir_spec(map() | String.t() | nil) :: Macro.t()
  def to_elixir_spec(nil), do: quote(do: term())

  def to_elixir_spec(descriptor) when is_binary(descriptor) do
    descriptor
    |> normalize_descriptor()
    |> do_to_elixir_spec()
  end

  def to_elixir_spec(descriptor) when is_map(descriptor) do
    # Normalize first if needed
    normalized =
      if Map.has_key?(descriptor, :kind) do
        descriptor
      else
        normalize_descriptor(descriptor)
      end

    do_to_elixir_spec(normalized)
  end

  # Primitives
  defp do_to_elixir_spec(%{kind: "primitive", primitive_type: "int"}), do: quote(do: integer())
  defp do_to_elixir_spec(%{kind: "primitive", primitive_type: "str"}), do: quote(do: String.t())
  defp do_to_elixir_spec(%{kind: "primitive", primitive_type: "float"}), do: quote(do: float())
  defp do_to_elixir_spec(%{kind: "primitive", primitive_type: "bool"}), do: quote(do: boolean())
  defp do_to_elixir_spec(%{kind: "primitive", primitive_type: "bytes"}), do: quote(do: binary())
  defp do_to_elixir_spec(%{kind: "primitive", primitive_type: "none"}), do: quote(do: nil)
  defp do_to_elixir_spec(%{kind: "primitive", primitive_type: "any"}), do: quote(do: term())

  # List
  defp do_to_elixir_spec(%{kind: "list", element_type: element}) do
    inner = to_elixir_spec(element)
    quote do: [unquote(inner)]
  end

  # Dict
  defp do_to_elixir_spec(%{kind: "dict", key_type: key, value_type: value}) do
    key_spec = to_elixir_spec(key)
    value_spec = to_elixir_spec(value)
    quote do: %{optional(unquote(key_spec)) => unquote(value_spec)}
  end

  # Tuple
  defp do_to_elixir_spec(%{kind: "tuple", element_types: types}) when is_list(types) do
    type_specs = Enum.map(types, &to_elixir_spec/1)

    {:{}, [], type_specs}
  end

  # Set
  defp do_to_elixir_spec(%{kind: "set", element_type: element}) do
    inner = to_elixir_spec(element)
    quote do: MapSet.t(unquote(inner))
  end

  # Union
  defp do_to_elixir_spec(%{kind: "union", union_types: types}) when is_list(types) do
    types
    |> Enum.map(&to_elixir_spec/1)
    |> Enum.reduce(fn spec, acc ->
      quote do: unquote(acc) | unquote(spec)
    end)
  end

  # Class
  defp do_to_elixir_spec(%{kind: "class", class_path: path}) do
    module = python_class_to_elixir_module(path)
    quote do: unquote(module).t()
  end

  # NumPy ndarray
  defp do_to_elixir_spec(%{kind: "ndarray", dtype: dtype}) when dtype in ["float64", "float32"] do
    quote do: list(float())
  end

  defp do_to_elixir_spec(%{kind: "ndarray", dtype: dtype})
       when dtype in ["int32", "int64", "int16", "int8", "uint8", "uint16", "uint32", "uint64"] do
    quote do: list(integer())
  end

  defp do_to_elixir_spec(%{kind: "ndarray"}) do
    quote do: list(number())
  end

  # DataFrame
  defp do_to_elixir_spec(%{kind: "dataframe"}) do
    quote do: list(map())
  end

  # Tensor
  defp do_to_elixir_spec(%{kind: "tensor"}) do
    quote do: list(number())
  end

  # Series
  defp do_to_elixir_spec(%{kind: "series"}) do
    quote do: list(term())
  end

  # Datetime types
  defp do_to_elixir_spec(%{kind: "datetime"}), do: quote(do: DateTime.t())
  defp do_to_elixir_spec(%{kind: "date"}), do: quote(do: Date.t())
  defp do_to_elixir_spec(%{kind: "time"}), do: quote(do: Time.t())
  defp do_to_elixir_spec(%{kind: "timedelta"}), do: quote(do: integer())

  # Callable
  defp do_to_elixir_spec(%{kind: "callable"}) do
    quote do: (... -> term())
  end

  # Generator types
  defp do_to_elixir_spec(%{kind: "generator"}), do: quote(do: Enumerable.t())
  defp do_to_elixir_spec(%{kind: "async_generator"}), do: quote(do: Enumerable.t())

  # Fallback
  defp do_to_elixir_spec(_), do: quote(do: term())

  @doc """
  Infer Python type from Elixir value.
  """
  def infer_python_type(value) when is_integer(value), do: :int
  def infer_python_type(value) when is_float(value), do: :float
  def infer_python_type(value) when is_binary(value), do: :str
  def infer_python_type(value) when is_boolean(value), do: :bool
  def infer_python_type(nil), do: :none

  def infer_python_type([]), do: {:list, :any}

  def infer_python_type([first | _]) do
    {:list, infer_python_type(first)}
  end

  def infer_python_type(map) when is_map(map) and map_size(map) == 0 do
    {:dict, :str, :any}
  end

  def infer_python_type(map) when is_map(map) do
    keys = Map.keys(map)
    vals = Map.values(map)

    if length(keys) > 0 do
      [key | _] = keys
      [_val | _] = vals

      # Infer key type - handle atoms by converting to string first
      key_type =
        if is_atom(key) do
          :str
        else
          infer_python_type(key)
        end

      # Infer value type - if multiple values have different types, use :any
      val_type =
        vals
        |> Enum.map(&infer_python_type/1)
        |> Enum.uniq()
        |> case do
          [single_type] -> single_type
          _ -> :any
        end

      {:dict, key_type, val_type}
    else
      {:dict, :str, :any}
    end
  end

  @doc """
  Convert Python class path to Elixir module atom.

  Handles atom length limits by using String.to_existing_atom when possible,
  or creating a safe shortened version.
  """
  def python_class_to_elixir_module(python_path) when is_binary(python_path) do
    # Convert python.module.Class to Elixir module atom
    # Capitalize each part, preserving acronyms (e.g., "ai" -> "AI")
    parts =
      python_path
      |> String.split(".")
      |> Enum.map(&smart_capitalize/1)

    module_string = Module.concat(parts) |> Atom.to_string()

    # Atoms have a 255 byte limit
    if byte_size(module_string) > 255 do
      # Use hash for very long paths
      hash = :crypto.hash(:sha256, python_path) |> Base.encode16() |> String.slice(0..7)
      String.to_atom("Module_#{hash}")
    else
      Module.concat(parts)
    end
  end

  # Smart capitalization that preserves common acronyms and CamelCase
  defp smart_capitalize("ai"), do: "AI"
  defp smart_capitalize("ml"), do: "ML"
  defp smart_capitalize("nlp"), do: "NLP"
  defp smart_capitalize("api"), do: "API"
  defp smart_capitalize("http"), do: "HTTP"
  defp smart_capitalize("json"), do: "Json"
  defp smart_capitalize("xml"), do: "XML"
  defp smart_capitalize("html"), do: "HTML"
  defp smart_capitalize("css"), do: "CSS"
  defp smart_capitalize("sql"), do: "SQL"
  defp smart_capitalize("db"), do: "DB"
  defp smart_capitalize("io"), do: "IO"
  defp smart_capitalize("os"), do: "OS"

  defp smart_capitalize(str) do
    # If string contains uppercase letters, it's likely already CamelCase - preserve it
    if String.match?(str, ~r/[A-Z]/) do
      str
    else
      String.capitalize(str)
    end
  end
end
