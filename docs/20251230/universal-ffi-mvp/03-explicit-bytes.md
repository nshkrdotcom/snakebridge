# Fix #3: Explicit Bytes Wrapper

**Status**: Specification
**Priority**: High
**Complexity**: Low
**Estimated Changes**: ~80 lines Elixir, ~20 lines Python

## Problem Statement

`SnakeBridge.Types.Encoder.encode/1` encodes Elixir binaries as:
- **string** if UTF-8 valid
- `{"__type__":"bytes"}` only if non-UTF-8

This makes it impossible to intentionally send bytes for common cases like `"abc"` to APIs that require bytes:

```elixir
# This fails because "abc" is sent as a Python str, not bytes
SnakeBridge.call("hashlib", "md5", ["abc"])
# => TypeError: Strings must be encoded before hashing

# Many crypto/binary APIs require bytes
SnakeBridge.call("base64", "b64encode", ["hello"])  # Fails
SnakeBridge.call("hmac", "new", [key, msg, "sha256"])  # Fails if key/msg are valid UTF-8
```

Current encoder behavior:

```elixir
def encode(binary) when is_binary(binary) do
  if String.valid?(binary) do
    binary  # UTF-8 valid → sends as string
  else
    tagged("bytes", %{"data" => Base.encode64(binary)})
  end
end
```

## Solution

Add an explicit bytes wrapper struct on the Elixir side that always encodes as Python `bytes`, regardless of UTF-8 validity.

### API Design

```elixir
# Create bytes explicitly
bytes = SnakeBridge.bytes("abc")
# => %SnakeBridge.Bytes{data: "abc"}

# Use in calls - always sent as Python bytes
{:ok, digest} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])
{:ok, encoded} = SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes("hello")])

# Works with any binary data
{:ok, _} = SnakeBridge.call("some_lib", "process", [SnakeBridge.bytes(<<0, 1, 2, 255>>)])
```

## Implementation Details

### File: `lib/snakebridge/bytes.ex` (NEW)

```elixir
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
  ```json
  {"__type__": "bytes", "__schema__": 1, "data": "<base64-encoded>"}
  ```
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
  """
  @spec data(t()) :: binary()
  def data(%__MODULE__{data: data}), do: data
end
```

### File: `lib/snakebridge.ex`

Add convenience function:

```elixir
@doc """
Creates a Bytes wrapper for explicit binary data encoding.

By default, SnakeBridge encodes UTF-8 valid strings as Python `str`.
Use this function when you need to send data as Python `bytes`.

## Examples

    # Hash data
    {:ok, hash} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])

    # Cryptographic operations
    key = SnakeBridge.bytes("secret_key")
    msg = SnakeBridge.bytes("message")
    {:ok, mac} = SnakeBridge.call("hmac", "new", [key, msg, "sha256"])

## When to Use

Python's type system distinguishes between `str` (text) and `bytes` (binary data).
Many APIs require bytes:

- `hashlib` - all hashing functions
- `base64` - encoding/decoding
- `struct` - binary packing/unpacking
- `cryptography` - encryption/decryption
- `socket` - network I/O
- File I/O in binary mode
"""
@spec bytes(binary()) :: SnakeBridge.Bytes.t()
def bytes(data) when is_binary(data) do
  SnakeBridge.Bytes.new(data)
end
```

### File: `lib/snakebridge/types/encoder.ex`

Add encoding clause for Bytes struct:

```elixir
@doc """
Encodes SnakeBridge.Bytes as Python bytes (always base64-encoded, never as string).
"""
def encode(%SnakeBridge.Bytes{data: data}) when is_binary(data) do
  tagged("bytes", %{"data" => Base.encode64(data)})
end

# Existing binary clause (for regular strings) - keep as is
def encode(binary) when is_binary(binary) do
  if String.valid?(binary) do
    binary
  else
    tagged("bytes", %{"data" => Base.encode64(binary)})
  end
end
```

**Important**: The `SnakeBridge.Bytes` clause must come **before** the generic binary clause.

### File: `priv/python/snakebridge_types.py`

The Python side already handles `{"__type__": "bytes"}` correctly:

```python
def decode_bytes(value):
    """Decode base64-encoded bytes."""
    data = value.get("data", "")
    return base64.b64decode(data)
```

No changes needed on Python side for decoding.

## Wire Format

**Elixir input**:
```elixir
SnakeBridge.bytes("abc")
```

**Wire format**:
```json
{
  "__type__": "bytes",
  "__schema__": 1,
  "data": "YWJj"
}
```

**Python result**:
```python
b"abc"
```

## Test Specifications

### File: `test/snakebridge/bytes_test.exs` (NEW)

```elixir
defmodule SnakeBridge.BytesTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Bytes

  describe "Bytes.new/1" do
    test "creates Bytes struct from string" do
      bytes = Bytes.new("hello")
      assert %Bytes{data: "hello"} = bytes
    end

    test "creates Bytes struct from binary" do
      bytes = Bytes.new(<<0, 1, 2, 255>>)
      assert %Bytes{data: <<0, 1, 2, 255>>} = bytes
    end

    test "creates Bytes struct from empty binary" do
      bytes = Bytes.new("")
      assert %Bytes{data: ""} = bytes
    end
  end

  describe "SnakeBridge.bytes/1" do
    test "convenience function creates Bytes" do
      bytes = SnakeBridge.bytes("test")
      assert %Bytes{data: "test"} = bytes
    end
  end

  describe "Bytes.data/1" do
    test "extracts data from Bytes struct" do
      bytes = Bytes.new("hello")
      assert Bytes.data(bytes) == "hello"
    end
  end
end
```

### File: `test/snakebridge/types/encoder_test.exs` (additions)

```elixir
describe "encode/1 Bytes struct" do
  test "encodes Bytes struct as bytes type" do
    bytes = SnakeBridge.Bytes.new("hello")
    encoded = Encoder.encode(bytes)

    assert %{
      "__type__" => "bytes",
      "__schema__" => 1,
      "data" => data
    } = encoded

    assert Base.decode64!(data) == "hello"
  end

  test "encodes UTF-8 string wrapped in Bytes as bytes, not string" do
    # Without wrapper, "abc" would be a string
    assert Encoder.encode("abc") == "abc"

    # With wrapper, it's bytes
    bytes = SnakeBridge.Bytes.new("abc")
    encoded = Encoder.encode(bytes)

    assert %{"__type__" => "bytes"} = encoded
  end

  test "encodes binary data in Bytes struct" do
    bytes = SnakeBridge.Bytes.new(<<0, 1, 2, 255>>)
    encoded = Encoder.encode(bytes)

    assert %{"__type__" => "bytes", "data" => data} = encoded
    assert Base.decode64!(data) == <<0, 1, 2, 255>>
  end

  test "encodes empty Bytes" do
    bytes = SnakeBridge.Bytes.new("")
    encoded = Encoder.encode(bytes)

    assert %{"__type__" => "bytes", "data" => ""} = encoded
  end
end
```

### File: `test/snakebridge/bytes_integration_test.exs` (NEW)

```elixir
defmodule SnakeBridge.BytesIntegrationTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  describe "bytes in Python calls" do
    test "hashlib.md5 with bytes" do
      # md5("abc") = 900150983cd24fb0d6963f7d28e17f72
      {:ok, ref} = SnakeBridge.call("hashlib", "md5", [SnakeBridge.bytes("abc")])
      {:ok, hex} = SnakeBridge.Dynamic.call(ref, :hexdigest, [])
      assert hex == "900150983cd24fb0d6963f7d28e17f72"
    end

    test "base64.b64encode with bytes" do
      {:ok, encoded} = SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes("hello")])
      # Returns bytes, which comes back as binary
      assert encoded == "aGVsbG8=" or encoded == SnakeBridge.bytes("aGVsbG8=")
    end

    test "len() works on bytes" do
      {:ok, length} = SnakeBridge.call("builtins", "len", [SnakeBridge.bytes("hello")])
      assert length == 5
    end

    test "bytes concatenation" do
      # b"hello" + b"world"
      b1 = SnakeBridge.bytes("hello")
      b2 = SnakeBridge.bytes("world")

      # Using operator module for + on bytes
      {:ok, result} = SnakeBridge.call("operator", "add", [b1, b2])
      # Result should be bytes
      assert result == "helloworld" or result == <<104, 101, 108, 108, 111, 119, 111, 114, 108, 100>>
    end
  end

  describe "bytes round-trip" do
    test "bytes returned from Python are decoded as binary" do
      # Python returns b"hello"
      {:ok, result} = SnakeBridge.call("base64", "b64decode", ["aGVsbG8="])
      assert result == "hello"
    end

    test "binary data round-trip" do
      original = <<0, 1, 2, 128, 255>>

      # Encode and decode via Python
      {:ok, encoded} = SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes(original)])
      {:ok, decoded} = SnakeBridge.call("base64", "b64decode", [encoded])

      assert decoded == original
    end
  end
end
```

## Edge Cases

1. **Empty bytes**: `SnakeBridge.bytes("")` should encode and decode correctly
2. **Large binary**: Should handle multi-megabyte binaries (limited by transport)
3. **All byte values**: `<<0..255>>` should round-trip correctly
4. **Unicode in bytes**: `SnakeBridge.bytes("日本語")` sends UTF-8 bytes, not str

## Performance Considerations

- Base64 encoding adds ~33% size overhead
- For large binaries, consider whether the Python API accepts file paths or streams instead
- Encoding/decoding is fast (native Base64 implementation)

## Backwards Compatibility

- **Fully backwards compatible**: Existing binary handling unchanged
- **Additive**: New struct and function
- **No wire format changes**: `{"__type__": "bytes"}` already supported

## Migration Guide

**Before** (workaround using non-UTF-8 marker):
```elixir
# Hack: add invalid UTF-8 to force bytes encoding, then strip in Python
data = "abc" <> <<255>>
# ... complex workaround
```

**After** (explicit and clear):
```elixir
data = SnakeBridge.bytes("abc")
{:ok, hash} = SnakeBridge.call("hashlib", "md5", [data])
```

## Common Use Cases

### Cryptography
```elixir
# Hash data
{:ok, ref} = SnakeBridge.call("hashlib", "sha256", [SnakeBridge.bytes(data)])
{:ok, digest} = SnakeBridge.Dynamic.call(ref, :digest, [])

# HMAC
{:ok, ref} = SnakeBridge.call("hmac", "new", [
  SnakeBridge.bytes(key),
  SnakeBridge.bytes(message),
  "sha256"
])
```

### Binary Protocols
```elixir
# Pack binary data
{:ok, packed} = SnakeBridge.call("struct", "pack", [">I", 12345])

# Network data
{:ok, _} = SnakeBridge.call("socket_lib", "send", [socket_ref, SnakeBridge.bytes(data)])
```

### Base64
```elixir
{:ok, encoded} = SnakeBridge.call("base64", "b64encode", [SnakeBridge.bytes("secret")])
{:ok, decoded} = SnakeBridge.call("base64", "b64decode", [encoded])
```

## Related Changes

- Used by [07-universal-api.md](./07-universal-api.md) in public API surface
- Complements [04-tagged-dict.md](./04-tagged-dict.md) for complete type coverage
