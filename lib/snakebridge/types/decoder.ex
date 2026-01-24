defmodule SnakeBridge.Types.Decoder do
  @moduledoc """
  Decodes JSON-compatible data from Python into Elixir data structures.

  Handles lossless decoding of tagged representations produced by the Python
  side or by `SnakeBridge.Types.Encoder`. Recognizes special `__type__` markers
  to reconstruct Elixir-specific types. Atom decoding is allowlist-based
  (configure via `:snakebridge, :atom_allowlist`).

  ## Supported Tagged Types

  - `{"__type__": "atom", "value": "ok"}` → `:ok` (allowlisted only)
  - `{"__type__": "tuple", "elements": [...]}` → Elixir tuple
  - `{"__type__": "set", "elements": [...]}` → MapSet
  - `{"__type__": "frozenset", "elements": [...]}` → MapSet
  - `{"__type__": "bytes", "data": "<base64>"}` → binary
  - `{"__type__": "datetime", "value": "<iso8601>"}` → DateTime
  - `{"__type__": "date", "value": "<iso8601>"}` → Date
  - `{"__type__": "time", "value": "<iso8601>"}` → Time
  - `{"__type__": "special_float", "value": "infinity"}` → `:infinity`
  - `{"__type__": "special_float", "value": "neg_infinity"}` → `:neg_infinity`
  - `{"__type__": "special_float", "value": "nan"}` → `:nan`
  - `{"__type__": "ref", ...}` → `SnakeBridge.Ref`
  - `{"__type__": "stream_ref", ...}` → `SnakeBridge.StreamRef`

  ## Direct JSON Types

  - `null` → `nil`
  - Booleans → `true`/`false`
  - Numbers → integers or floats
  - Strings → strings
  - Arrays → lists (recursively decoded)
  - Objects → maps with string keys (recursively decoded)

  ## Examples

      iex> SnakeBridge.Types.Decoder.decode(%{"__type__" => "tuple", "elements" => [1, 2, 3]})
      {1, 2, 3}

      iex> SnakeBridge.Types.Decoder.decode(%{"__type__" => "set", "elements" => [1, 2, 3]})
      #MapSet<[1, 2, 3]>

      iex> SnakeBridge.Types.Decoder.decode(%{"a" => 1, "b" => 2})
      %{"a" => 1, "b" => 2}

  """

  @doc """
  Decodes a JSON-compatible value into an Elixir data structure.

  Recognizes and handles tagged types from the Python encoder.

  ## Examples

      iex> decode(42)
      42

      iex> decode([1, 2, 3])
      [1, 2, 3]

      iex> decode(%{
      ...>   "__type__" => "tuple",
      ...>   "elements" => [%{"__type__" => "atom", "value" => "ok"}, "result"]
      ...> })
      {:ok, "result"}

  """
  @spec decode(term()) :: term()
  def decode(nil), do: nil
  def decode(true), do: true
  def decode(false), do: false
  def decode(num) when is_number(num), do: num
  def decode(str) when is_binary(str), do: str

  # Lists - recursively decode elements
  def decode(list) when is_list(list) do
    Enum.map(list, &decode/1)
  end

  def decode(%{"__type__" => "stream_ref"} = map) do
    SnakeBridge.StreamRef.from_wire_format(map)
  end

  def decode(%{"__type__" => "ref"} = ref) do
    required = ["id", "session_id"]
    missing = Enum.filter(required, &(not Map.has_key?(ref, &1)))

    if missing != [] do
      raise ArgumentError, "Invalid ref: missing fields #{inspect(missing)}"
    end

    ref_struct = SnakeBridge.Ref.from_wire_format(ref)
    maybe_register_ref(ref_struct)
    ref_struct
  end

  # Maps with __type__ markers - decode based on type
  def decode(%{"__type__" => "atom"} = map) do
    value = Map.get(map, "value")

    if is_binary(value) and atom_allowed?(value) do
      String.to_atom(value)
    else
      value
    end
  end

  def decode(%{"__type__" => "tuple"} = map) do
    map
    |> list_field()
    |> Enum.map(&decode/1)
    |> List.to_tuple()
  end

  def decode(%{"__type__" => "set"} = map) do
    map
    |> list_field()
    |> Enum.map(&decode/1)
    |> MapSet.new()
  end

  def decode(%{"__type__" => "frozenset"} = map) do
    map
    |> list_field()
    |> Enum.map(&decode/1)
    |> MapSet.new()
  end

  def decode(%{"__type__" => "bytes"} = map) do
    data = Map.get(map, "data") || Map.get(map, "value")

    if is_binary(data) do
      case Base.decode64(data) do
        {:ok, binary} -> binary
        :error -> data
      end
    else
      data
    end
  end

  def decode(%{"__type__" => "datetime", "value" => value}) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> value
    end
  end

  def decode(%{"__type__" => "date", "value" => value}) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _} -> value
    end
  end

  def decode(%{"__type__" => "time", "value" => value}) when is_binary(value) do
    case Time.from_iso8601(value) do
      {:ok, time} -> time
      {:error, _} -> value
    end
  end

  def decode(%{"__type__" => "special_float", "value" => "infinity"}), do: :infinity
  def decode(%{"__type__" => "special_float", "value" => "neg_infinity"}), do: :neg_infinity
  def decode(%{"__type__" => "special_float", "value" => "nan"}), do: :nan
  def decode(%{"__type__" => "infinity"}), do: :infinity
  def decode(%{"__type__" => "neg_infinity"}), do: :neg_infinity
  def decode(%{"__type__" => "nan"}), do: :nan

  def decode(%{"__type__" => "complex", "real" => real, "imag" => imag}) do
    %{real: real, imag: imag}
  end

  # Tagged dict - maps with non-string keys
  def decode(%{"__type__" => "dict", "pairs" => pairs}) when is_list(pairs) do
    pairs
    |> Enum.map(fn
      [key, value] ->
        {decode(key), decode(value)}

      pair when is_list(pair) and length(pair) == 2 ->
        [key, value] = pair
        {decode(key), decode(value)}
    end)
    |> Map.new()
  end

  # Tagged dict with schema version
  def decode(%{"__type__" => "dict", "__schema__" => _schema, "pairs" => pairs}) do
    decode(%{"__type__" => "dict", "pairs" => pairs})
  end

  # Regular maps - recursively decode values
  def decode(%{} = map) do
    Map.new(map, fn {key, value} ->
      {key, decode(value)}
    end)
  end

  # Anything else passes through unchanged
  def decode(other), do: other

  defp list_field(map) do
    case Map.get(map, "elements") do
      nil -> Map.get(map, "value", [])
      elements -> elements
    end
    |> List.wrap()
  end

  defp atom_allowed?(value) when is_binary(value) do
    case atom_allowlist() do
      :all -> true
      allowlist -> value in allowlist
    end
  end

  defp atom_allowed?(_), do: false

  defp atom_allowlist do
    case SnakeBridge.Env.app_env(:snakebridge, :atom_allowlist, ["ok", "error"]) do
      :all -> :all
      list -> Enum.map(List.wrap(list), &to_string/1)
    end
  end

  defp maybe_register_ref(ref) do
    session_id = Map.get(ref, "session_id") || Map.get(ref, :session_id)

    if is_binary(session_id) and Process.whereis(SnakeBridge.SessionManager) do
      case SnakeBridge.SessionManager.register_ref(session_id, ref) do
        :ok -> :ok
        {:error, _reason} -> :ok
      end
    end

    :ok
  end
end
