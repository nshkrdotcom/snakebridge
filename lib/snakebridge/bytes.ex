defmodule SnakeBridge.Bytes do
  @moduledoc """
  Wrapper struct for binary data that should be sent to Python as `bytes`, not `str`.

  By default, SnakeBridge encodes UTF-8 valid Elixir binaries as Python strings.
  Use this wrapper when you need to explicitly send data as Python bytes.

  ## Examples

      # Hash a string as bytes
      {:ok, hash} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])

      # Base64 encode
      {:ok, encoded} = SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes("hello")])

      # Binary protocol data
      {:ok, _} = SnakeBridge.call("struct", "pack", [">I", 42])

  ## When to Use

  Use `SnakeBridge.bytes/1` when calling Python functions that:
  - Require `bytes` input (hashlib, cryptography, struct, etc.)
  - Work with binary protocols
  - Process raw byte data

  ## Wire Format

  Encoded as:

      {"__type__": "bytes", "__schema__": 1, "data": "<base64-encoded>"}

  """

  @type t :: %__MODULE__{data: binary()}

  defstruct [:data]

  @doc """
  Creates a Bytes wrapper from binary data.

  ## Examples

      iex> SnakeBridge.Bytes.new("hello")
      %SnakeBridge.Bytes{data: "hello"}

      iex> SnakeBridge.Bytes.new(<<0, 1, 2, 255>>)
      %SnakeBridge.Bytes{data: <<0, 1, 2, 255>>}

  """
  @spec new(binary()) :: t()
  def new(data) when is_binary(data) do
    %__MODULE__{data: data}
  end

  @doc """
  Returns the raw binary data from a Bytes wrapper.

  ## Examples

      iex> bytes = SnakeBridge.Bytes.new("hello")
      iex> SnakeBridge.Bytes.data(bytes)
      "hello"

  """
  @spec data(t()) :: binary()
  def data(%__MODULE__{data: data}), do: data
end
