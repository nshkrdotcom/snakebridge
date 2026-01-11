defmodule SnakeBridge.Ref do
  @moduledoc """
  Structured reference to a Python object managed by SnakeBridge.

  This struct defines the cross-language wire shape for Python object references.
  """

  @schema_version 1

  @typedoc """
  Structured reference to a Python object.
  """
  @type t :: %__MODULE__{
          id: String.t(),
          session_id: String.t(),
          pool_name: String.t() | atom() | nil,
          python_module: String.t() | nil,
          library: String.t() | nil,
          type_name: String.t() | nil,
          schema: pos_integer()
        }

  defstruct [
    :id,
    :session_id,
    :pool_name,
    :python_module,
    :library,
    :type_name,
    schema: @schema_version
  ]

  @spec schema_version() :: pos_integer()
  def schema_version, do: @schema_version

  @doc """
  Creates a Ref from a wire format map.
  """
  @spec from_wire_format(map() | t()) :: t()
  def from_wire_format(%__MODULE__{} = ref), do: ref

  def from_wire_format(map) when is_map(map) do
    %__MODULE__{
      id: get_wire_field(map, ["id", "ref_id"]),
      session_id: get_wire_field(map, ["session_id"]),
      pool_name: get_wire_field(map, ["pool_name"]),
      python_module: get_wire_field(map, ["python_module"]),
      library: get_wire_field(map, ["library"]),
      type_name: get_wire_field(map, ["type_name", "__type_name__"]),
      schema: get_wire_field(map, ["__schema__", "schema"]) || @schema_version
    }
  end

  defp get_wire_field(map, keys) do
    Enum.find_value(keys, fn key ->
      Map.get(map, key) || Map.get(map, String.to_atom(key))
    end)
  end

  @doc """
  Converts a Ref to wire format for Python calls.
  """
  @spec to_wire_format(t() | map()) :: map()
  def to_wire_format(%__MODULE__{} = ref) do
    %{}
    |> Map.put("__type__", "ref")
    |> Map.put("__schema__", ref.schema || @schema_version)
    |> maybe_put("id", ref.id)
    |> maybe_put("session_id", ref.session_id)
    |> maybe_put("python_module", ref.python_module)
    |> maybe_put("library", ref.library)
  end

  def to_wire_format(%{"__type__" => "ref"} = ref) do
    ref
    |> from_wire_format()
    |> to_wire_format()
  end

  def to_wire_format(%{__type__: "ref"} = ref) do
    ref
    |> from_wire_format()
    |> to_wire_format()
  end

  @doc """
  Checks if a value is a valid ref.
  """
  @spec ref?(term()) :: boolean()
  def ref?(%__MODULE__{id: id, session_id: session_id})
      when is_binary(id) and is_binary(session_id),
      do: true

  def ref?(%{"__type__" => "ref"} = ref) do
    ref_id =
      Map.get(ref, "id") || Map.get(ref, :id) || Map.get(ref, "ref_id") || Map.get(ref, :ref_id)

    session_id = Map.get(ref, "session_id") || Map.get(ref, :session_id)
    is_binary(ref_id) and is_binary(session_id)
  end

  def ref?(%{__type__: "ref"} = ref), do: ref?(Map.new(ref, fn {k, v} -> {to_string(k), v} end))

  def ref?(_), do: false

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defimpl Inspect, for: SnakeBridge.Ref do
  import Inspect.Algebra

  alias SnakeBridge.Ref
  alias SnakeBridge.Runtime

  def inspect(%Ref{} = ref, _opts) do
    case python_repr(ref) do
      {:ok, repr} when is_binary(repr) ->
        concat(["#Python<", repr, ">"])

      _ ->
        concat(["#SnakeBridge.Ref<", to_string(ref.id || "unknown"), ">"])
    end
  end

  defp python_repr(ref) do
    case safe_call(ref, :__repr__) do
      {:ok, repr} when is_binary(repr) ->
        {:ok, repr}

      _ ->
        python_str(ref)
    end
  end

  defp python_str(ref) do
    case safe_call(ref, :__str__) do
      {:ok, str} when is_binary(str) -> {:ok, str}
      _ -> {:error, :unavailable}
    end
  end

  defp safe_call(ref, method) do
    Runtime.call_method(ref, method, [])
  rescue
    exception -> {:error, exception}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end
end

defimpl String.Chars, for: SnakeBridge.Ref do
  alias SnakeBridge.Ref
  alias SnakeBridge.Runtime

  def to_string(%Ref{} = ref) do
    case safe_call(ref, :__str__) do
      {:ok, str} when is_binary(str) -> str
      _ -> "#SnakeBridge.Ref<#{ref.id || "unknown"}>"
    end
  end

  defp safe_call(ref, method) do
    Runtime.call_method(ref, method, [])
  rescue
    exception -> {:error, exception}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end
end

defimpl Enumerable, for: SnakeBridge.Ref do
  alias SnakeBridge.Runtime
  alias SnakeBridge.StreamRef

  def count(ref) do
    case safe_call(ref, :__len__, []) do
      {:ok, len} when is_integer(len) -> {:ok, len}
      _ -> {:error, __MODULE__}
    end
  end

  def member?(ref, value) do
    case safe_call(ref, :__contains__, [value]) do
      {:ok, result} when is_boolean(result) -> {:ok, result}
      _ -> {:error, __MODULE__}
    end
  end

  def slice(_ref), do: {:error, __MODULE__}

  def reduce(ref, acc, fun) do
    case safe_call(ref, :__iter__, []) do
      {:ok, %StreamRef{} = stream_ref} ->
        Enumerable.reduce(stream_ref, acc, fun)

      {:ok, iterator_ref} ->
        do_reduce(iterator_ref, acc, fun)

      {:error, _} ->
        do_reduce_by_index(ref, 0, acc, fun)
    end
  end

  defp do_reduce(_iterator, {:halt, acc}, _fun), do: {:halted, acc}

  defp do_reduce(iterator, {:suspend, acc}, fun) do
    {:suspended, acc, &do_reduce(iterator, &1, fun)}
  end

  defp do_reduce(iterator, {:cont, acc}, fun) do
    case safe_call(iterator, :__next__, []) do
      {:ok, value} ->
        do_reduce(iterator, fun.(value, acc), fun)

      {:error, reason} ->
        if stop_iteration?(reason) do
          {:done, acc}
        else
          {:halted, {:error, reason}}
        end
    end
  end

  defp do_reduce_by_index(_ref, _index, {:halt, acc}, _fun), do: {:halted, acc}

  defp do_reduce_by_index(ref, index, {:suspend, acc}, fun) do
    {:suspended, acc, &do_reduce_by_index(ref, index, &1, fun)}
  end

  defp do_reduce_by_index(ref, index, {:cont, acc}, fun) do
    case safe_call(ref, :__getitem__, [index]) do
      {:ok, value} ->
        do_reduce_by_index(ref, index + 1, fun.(value, acc), fun)

      {:error, reason} ->
        if index_error?(reason) or stop_iteration?(reason) do
          {:done, acc}
        else
          {:halted, {:error, reason}}
        end
    end
  end

  defp safe_call(ref, method, args) do
    Runtime.call_method(ref, method, args)
  rescue
    exception -> {:error, exception}
  end

  defp stop_iteration?(reason), do: error_type(reason) == "StopIteration"
  defp index_error?(reason), do: error_type(reason) == "IndexError"

  defp error_type(%{python_class: class}) when is_binary(class) do
    class
    |> String.split(".")
    |> List.last()
  end

  # Check for python_type field (these are atom-keyed struct fields)
  defp error_type(%{python_type: type}) when is_binary(type), do: type
  defp error_type(%{python_type: type}) when is_atom(type), do: Atom.to_string(type)

  # Check for error_type field
  defp error_type(%{error_type: type}) when is_binary(type), do: type
  defp error_type(%{error_type: type}) when is_atom(type), do: Atom.to_string(type)

  # Check for type field
  defp error_type(%{type: type}) when is_binary(type), do: type
  defp error_type(%{type: type}) when is_atom(type), do: Atom.to_string(type)

  # Handle exception structs by extracting the module name
  defp error_type(%{__struct__: struct}) do
    struct
    |> Module.split()
    |> List.last()
  end
end
