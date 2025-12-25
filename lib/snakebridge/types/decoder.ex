defmodule SnakeBridge.Types.Decoder do
  @moduledoc """
  Decodes JSON-compatible data from Python into Elixir data structures.

  Handles lossless decoding of tagged representations produced by the Python
  side or by `SnakeBridge.Types.Encoder`. Recognizes special `__type__` markers
  to reconstruct Elixir-specific types.

  ## Supported Tagged Types

  - `{"__type__": "tuple", "elements": [...]}` → Elixir tuple
  - `{"__type__": "set", "elements": [...]}` → MapSet
  - `{"__type__": "bytes", "data": "<base64>"}` → binary
  - `{"__type__": "datetime", "value": "<iso8601>"}` → DateTime
  - `{"__type__": "date", "value": "<iso8601>"}` → Date
  - `{"__type__": "time", "value": "<iso8601>"}` → Time
  - `{"__type__": "special_float", "value": "infinity"}` → `:infinity`
  - `{"__type__": "special_float", "value": "neg_infinity"}` → `:neg_infinity`
  - `{"__type__": "special_float", "value": "nan"}` → `:nan`

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

      iex> decode(%{"__type__" => "tuple", "elements" => ["ok", "result"]})
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

  # Maps with __type__ markers - decode based on type
  def decode(%{"__type__" => "tuple", "elements" => elements}) when is_list(elements) do
    elements
    |> Enum.map(&decode/1)
    |> List.to_tuple()
  end

  def decode(%{"__type__" => "set", "elements" => elements}) when is_list(elements) do
    elements
    |> Enum.map(&decode/1)
    |> MapSet.new()
  end

  def decode(%{"__type__" => "bytes", "data" => data}) when is_binary(data) do
    case Base.decode64(data) do
      {:ok, binary} -> binary
      :error -> data
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

  def decode(%{"__type__" => "complex", "real" => real, "imag" => imag}) do
    %{real: real, imag: imag}
  end

  # Regular maps - recursively decode values
  def decode(%{} = map) do
    Map.new(map, fn {key, value} ->
      {key, decode(value)}
    end)
  end

  # Anything else passes through unchanged
  def decode(other), do: other
end
