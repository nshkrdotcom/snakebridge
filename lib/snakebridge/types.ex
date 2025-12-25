defmodule SnakeBridge.Types do
  @moduledoc """
  Public API for encoding and decoding Elixir types for Python interop.

  This module provides a unified interface for type conversion between Elixir
  and Python. It handles the serialization of Elixir-specific types (tuples,
  MapSets, DateTime, etc.) into JSON-compatible formats and vice versa.

  ## Usage

      # Encoding Elixir to JSON-compatible format
      iex> SnakeBridge.Types.encode({:ok, 42})
      %{"__type__" => "tuple", "elements" => ["ok", 42]}

      # Decoding JSON-compatible format back to Elixir
      iex> SnakeBridge.Types.decode(%{"__type__" => "tuple", "elements" => ["ok", 42]})
      {"ok", 42}

  ## Type System

  The type system uses tagged JSON representations to preserve type information
  across the Elixir-Python boundary. See `SnakeBridge.Types.Encoder` and
  `SnakeBridge.Types.Decoder` for details on supported types and their
  representations.

  ## Round-trip Safety

  All encoded values can be round-tripped:

      iex> data = {:ok, MapSet.new([1, 2, 3])}
      iex> data |> SnakeBridge.Types.encode() |> SnakeBridge.Types.decode()
      {"ok", MapSet.new([1, 2, 3])}
  """

  alias SnakeBridge.Types.{Encoder, Decoder}

  @doc """
  Encodes an Elixir value into a JSON-compatible structure.

  Delegates to `SnakeBridge.Types.Encoder.encode/1`.

  ## Examples

      iex> SnakeBridge.Types.encode(:ok)
      "ok"

      iex> SnakeBridge.Types.encode({:ok, 42})
      %{"__type__" => "tuple", "elements" => ["ok", 42]}

      iex> SnakeBridge.Types.encode(MapSet.new([1, 2, 3]))
      %{"__type__" => "set", "elements" => [1, 2, 3]}
  """
  @spec encode(term()) :: term()
  defdelegate encode(value), to: Encoder

  @doc """
  Decodes a JSON-compatible structure back into Elixir types.

  Delegates to `SnakeBridge.Types.Decoder.decode/1`.

  ## Examples

      iex> SnakeBridge.Types.decode("ok")
      "ok"

      iex> SnakeBridge.Types.decode(%{"__type__" => "tuple", "elements" => ["ok", 42]})
      {"ok", 42}

      iex> SnakeBridge.Types.decode(%{"__type__" => "set", "elements" => [1, 2, 3]})
      MapSet.new([1, 2, 3])
  """
  @spec decode(term()) :: term()
  defdelegate decode(value), to: Decoder
end
