defmodule SnakeBridge.Types.Encoder do
  @moduledoc """
  Encodes Elixir data structures into JSON-compatible formats for Python interop.

  Handles lossless encoding of Elixir types that don't have direct JSON equivalents
  using tagged representations. Tagged values include a `__schema__` marker for
  the current wire schema version. Atom round-trips depend on the decoder
  allowlist.

  ## Supported Types

  ### Direct JSON Types
  - `nil` → `null`
  - Booleans → `true`/`false`
  - Integers → numbers
  - Floats → numbers
  - Strings (UTF-8) → strings
  - Lists → arrays
  - Maps with string keys → objects

  ### Tagged Types
  - Atoms → `{"__type__": "atom", "value": "ok"}`
  - Tuples → `{"__type__": "tuple", "elements": [...]}`
  - MapSets → `{"__type__": "set", "elements": [...]}`
  - Binaries (non-UTF-8) → `{"__type__": "bytes", "data": "<base64>"}`
  - DateTime → `{"__type__": "datetime", "value": "<iso8601>"}`
  - Date → `{"__type__": "date", "value": "<iso8601>"}`
  - Time → `{"__type__": "time", "value": "<iso8601>"}`
  - Special floats → `{"__type__": "special_float", "value": "infinity"|"neg_infinity"|"nan"}`
  - Maps with atom keys → converted to string keys

  ## Examples

      iex> SnakeBridge.Types.Encoder.encode(%{a: 1, b: 2})
      %{"a" => 1, "b" => 2}

      iex> SnakeBridge.Types.Encoder.encode({:ok, "result"})
      %{
        "__type__" => "tuple",
        "__schema__" => 1,
        "elements" => [%{"__type__" => "atom", "__schema__" => 1, "value" => "ok"}, "result"]
      }

      iex> SnakeBridge.Types.Encoder.encode(MapSet.new([1, 2, 3]))
      %{"__type__" => "set", "__schema__" => 1, "elements" => [1, 2, 3]}

  """

  @doc """
  Encodes an Elixir value into a JSON-compatible structure.

  ## Examples

      iex> encode(42)
      42

      iex> encode(:ok)
      %{"__type__" => "atom", "__schema__" => 1, "value" => "ok"}

      iex> encode({1, 2, 3})
      %{"__type__" => "tuple", "__schema__" => 1, "elements" => [1, 2, 3]}

  """
  @spec encode(term()) :: term()
  def encode(nil), do: nil
  def encode(true), do: true
  def encode(false), do: false

  # Special float atoms
  def encode(:infinity), do: tagged("special_float", %{"value" => "infinity"})
  def encode(:neg_infinity), do: tagged("special_float", %{"value" => "neg_infinity"})
  def encode(:nan), do: tagged("special_float", %{"value" => "nan"})

  # Regular atoms are tagged for lossless interop
  def encode(atom) when is_atom(atom) do
    tagged("atom", %{"value" => Atom.to_string(atom)})
  end

  # Numbers
  def encode(num) when is_integer(num), do: num
  def encode(num) when is_float(num), do: num

  # Strings and binaries
  def encode(binary) when is_binary(binary) do
    if String.valid?(binary) do
      binary
    else
      # Non-UTF-8 binary - encode as base64
      tagged("bytes", %{"data" => Base.encode64(binary)})
    end
  end

  # Lists
  def encode(list) when is_list(list) do
    Enum.map(list, &encode/1)
  end

  # Tuples
  def encode(tuple) when is_tuple(tuple) do
    tagged("tuple", %{"elements" => tuple |> Tuple.to_list() |> Enum.map(&encode/1)})
  end

  # MapSets
  def encode(%MapSet{} = mapset) do
    tagged("set", %{"elements" => mapset |> MapSet.to_list() |> Enum.map(&encode/1)})
  end

  # DateTime
  def encode(%DateTime{} = dt) do
    tagged("datetime", %{"value" => DateTime.to_iso8601(dt)})
  end

  # Date
  def encode(%Date{} = date) do
    tagged("date", %{"value" => Date.to_iso8601(date)})
  end

  # Time
  def encode(%Time{} = time) do
    tagged("time", %{"value" => Time.to_iso8601(time)})
  end

  # Snakepit PyRef - normalize to ref wire shape
  def encode(%{__struct__: Snakepit.PyRef} = ref) do
    ref
    |> Map.from_struct()
    |> normalize_pyref_map()
  end

  # SnakeBridge Ref - normalize to ref wire shape
  def encode(%SnakeBridge.Ref{} = ref) do
    SnakeBridge.Ref.to_wire_format(ref)
  end

  # Functions - encode as callback references
  def encode(fun) when is_function(fun) do
    {:ok, callback_id} = SnakeBridge.CallbackRegistry.register(fun)
    arity = Function.info(fun)[:arity]

    tagged("callback", %{
      "ref_id" => callback_id,
      "pid" => self() |> :erlang.pid_to_list() |> IO.iodata_to_binary(),
      "arity" => arity
    })
  end

  # Maps - convert atom keys to strings, recursively encode values
  def encode(%{} = map) do
    Map.new(map, fn {key, value} ->
      encoded_key =
        cond do
          is_atom(key) and key not in [nil, true, false] -> Atom.to_string(key)
          is_binary(key) -> key
          true -> encode(key)
        end

      {encoded_key, encode(value)}
    end)
  end

  # Fallback for any other type - convert to string representation
  def encode(other) do
    inspect(other)
  end

  defp tagged(type, fields) when is_map(fields) do
    fields
    |> Map.put("__type__", type)
    |> Map.put("__schema__", SnakeBridge.Types.schema_version())
  end

  defp normalize_pyref_map(ref) do
    ref_id = Map.get(ref, :id) || Map.get(ref, :ref_id)

    %{}
    |> Map.put("__type__", "ref")
    |> Map.put("__schema__", SnakeBridge.Ref.schema_version())
    |> maybe_put("id", ref_id)
    |> maybe_put("session_id", Map.get(ref, :session_id))
    |> maybe_put("python_module", Map.get(ref, :python_module))
    |> maybe_put("library", Map.get(ref, :library))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
