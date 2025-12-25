# stateless_examples.exs
# Auto-generated examples for SnakeBridge.Base64
# Run with: mix run examples/generated/base64/stateless_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Base64 Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# a85decode [○ stateless]
# Decode the Ascii85 encoded bytes-like object or ASCII string b.
IO.puts("Testing a85decode...")

try do
  result = SnakeBridge.Base64.a85decode(%{b: "87cURDZ"})
  IO.puts("  ✓ a85decode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ a85decode: #{Exception.message(e)}")
end

# a85encode [○ stateless]
# Encode bytes-like object b using Ascii85 and return a bytes object.
IO.puts("Testing a85encode...")

try do
  result = SnakeBridge.Base64.a85encode(%{b: <<72, 101, 108, 108, 111>>})
  IO.puts("  ✓ a85encode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ a85encode: #{Exception.message(e)}")
end

# b16decode [○ stateless]
# Decode the Base16 encoded bytes-like object or ASCII string s.
IO.puts("Testing b16decode...")

try do
  result = SnakeBridge.Base64.b16decode(%{s: "48656C6C6F"})
  IO.puts("  ✓ b16decode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ b16decode: #{Exception.message(e)}")
end

# b16encode [○ stateless]
# Encode the bytes-like object s using Base16 and return a bytes object.
IO.puts("Testing b16encode...")

try do
  result = SnakeBridge.Base64.b16encode(%{s: <<72, 101, 108, 108, 111>>})
  IO.puts("  ✓ b16encode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ b16encode: #{Exception.message(e)}")
end

# b32decode [○ stateless]
# Decode the base32 encoded bytes-like object or ASCII string s.
IO.puts("Testing b32decode...")

try do
  result = SnakeBridge.Base64.b32decode(%{s: "JBSWY3DP"})
  IO.puts("  ✓ b32decode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ b32decode: #{Exception.message(e)}")
end

# b32encode [○ stateless]
# Encode the bytes-like objects using base32 and return a bytes object.
IO.puts("Testing b32encode...")

try do
  result = SnakeBridge.Base64.b32encode(%{s: <<72, 101, 108, 108, 111>>})
  IO.puts("  ✓ b32encode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ b32encode: #{Exception.message(e)}")
end

# b32hexdecode [○ stateless]
# Decode the base32hex encoded bytes-like object or ASCII string s.
IO.puts("Testing b32hexdecode...")

try do
  result = SnakeBridge.Base64.b32hexdecode(%{s: "91IMOR3F"})
  IO.puts("  ✓ b32hexdecode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ b32hexdecode: #{Exception.message(e)}")
end

# b32hexencode [○ stateless]
# Encode the bytes-like objects using base32hex and return a bytes objec
IO.puts("Testing b32hexencode...")

try do
  result = SnakeBridge.Base64.b32hexencode(%{s: <<72, 101, 108, 108, 111>>})
  IO.puts("  ✓ b32hexencode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ b32hexencode: #{Exception.message(e)}")
end

# b85decode [○ stateless]
# Decode the base85-encoded bytes-like object or ASCII string b
IO.puts("Testing b85decode...")

try do
  result = SnakeBridge.Base64.b85decode(%{b: "NM&qnZv"})
  IO.puts("  ✓ b85decode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ b85decode: #{Exception.message(e)}")
end

# b85encode [○ stateless]
# Encode bytes-like object b in base85 format and return a bytes object.
IO.puts("Testing b85encode...")

try do
  result = SnakeBridge.Base64.b85encode(%{b: <<72, 101, 108, 108, 111>>})
  IO.puts("  ✓ b85encode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ b85encode: #{Exception.message(e)}")
end

# decodebytes [○ stateless]
# Decode a bytestring of base-64 data into a bytes object.
IO.puts("Testing decodebytes...")

try do
  result = SnakeBridge.Base64.decodebytes(%{s: "SGVsbG8="})
  IO.puts("  ✓ decodebytes: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ decodebytes: #{Exception.message(e)}")
end

# encodebytes [○ stateless]
# Encode a bytestring into a bytes object containing multiple lines
IO.puts("Testing encodebytes...")

try do
  result = SnakeBridge.Base64.encodebytes(%{s: <<72, 101, 108, 108, 111>>})
  IO.puts("  ✓ encodebytes: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ encodebytes: #{Exception.message(e)}")
end

# standard_b64decode [○ stateless]
# Decode bytes encoded with the standard Base64 alphabet.
IO.puts("Testing standard_b64decode...")

try do
  result = SnakeBridge.Base64.standard_b64decode(%{s: "SGVsbG8="})
  IO.puts("  ✓ standard_b64decode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ standard_b64decode: #{Exception.message(e)}")
end

# standard_b64encode [○ stateless]
# Encode bytes-like object s using the standard Base64 alphabet.
IO.puts("Testing standard_b64encode...")

try do
  result = SnakeBridge.Base64.standard_b64encode(%{s: <<72, 101, 108, 108, 111>>})
  IO.puts("  ✓ standard_b64encode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ standard_b64encode: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
