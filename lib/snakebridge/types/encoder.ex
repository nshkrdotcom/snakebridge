defmodule SnakeBridge.Types.Encoder do
  @moduledoc """
  Encodes Elixir data structures into JSON-compatible formats for Python interop.

  Handles lossless encoding of Elixir types that don't have direct JSON equivalents
  using tagged representations. All encoded values can be round-tripped through
  the corresponding Decoder.

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
  - Atoms → strings (except `nil`, `true`, `false`)
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
      %{"__type__" => "tuple", "elements" => ["ok", "result"]}

      iex> SnakeBridge.Types.Encoder.encode(MapSet.new([1, 2, 3]))
      %{"__type__" => "set", "elements" => [1, 2, 3]}

  """

  @doc """
  Encodes an Elixir value into a JSON-compatible structure.

  ## Examples

      iex> encode(42)
      42

      iex> encode(:ok)
      "ok"

      iex> encode({1, 2, 3})
      %{"__type__" => "tuple", "elements" => [1, 2, 3]}

  """
  @spec encode(term()) :: term()
  def encode(nil), do: nil
  def encode(true), do: true
  def encode(false), do: false

  # Special float atoms
  def encode(:infinity), do: %{"__type__" => "special_float", "value" => "infinity"}
  def encode(:neg_infinity), do: %{"__type__" => "special_float", "value" => "neg_infinity"}
  def encode(:nan), do: %{"__type__" => "special_float", "value" => "nan"}

  # Regular atoms become strings
  def encode(atom) when is_atom(atom), do: Atom.to_string(atom)

  # Numbers
  def encode(num) when is_integer(num), do: num
  def encode(num) when is_float(num), do: num

  # Strings and binaries
  def encode(binary) when is_binary(binary) do
    if String.valid?(binary) do
      binary
    else
      # Non-UTF-8 binary - encode as base64
      %{
        "__type__" => "bytes",
        "data" => Base.encode64(binary)
      }
    end
  end

  # Lists
  def encode(list) when is_list(list) do
    Enum.map(list, &encode/1)
  end

  # Tuples
  def encode(tuple) when is_tuple(tuple) do
    %{
      "__type__" => "tuple",
      "elements" => tuple |> Tuple.to_list() |> Enum.map(&encode/1)
    }
  end

  # MapSets
  def encode(%MapSet{} = mapset) do
    %{
      "__type__" => "set",
      "elements" => mapset |> MapSet.to_list() |> Enum.map(&encode/1)
    }
  end

  # DateTime
  def encode(%DateTime{} = dt) do
    %{
      "__type__" => "datetime",
      "value" => DateTime.to_iso8601(dt)
    }
  end

  # Date
  def encode(%Date{} = date) do
    %{
      "__type__" => "date",
      "value" => Date.to_iso8601(date)
    }
  end

  # Time
  def encode(%Time{} = time) do
    %{
      "__type__" => "time",
      "value" => Time.to_iso8601(time)
    }
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
end
