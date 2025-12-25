# stateful_examples.exs
# Auto-generated examples for SnakeBridge.Base64
# Run with: mix run examples/generated/base64/stateful_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Base64 Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# b64decode [● stateful]
# Decode the Base64 encoded bytes-like object or ASCII string s.
IO.puts("Testing b64decode...")

try do
  result = SnakeBridge.Base64.b64decode(%{s: "SGVsbG8="})
  IO.puts("  ✓ b64decode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ b64decode: #{Exception.message(e)}")
end

# b64encode [● stateful]
# Encode the bytes-like object s using Base64 and return a bytes object.
IO.puts("Testing b64encode...")

try do
  result = SnakeBridge.Base64.b64encode(%{s: <<72, 101, 108, 108, 111>>})
  IO.puts("  ✓ b64encode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ b64encode: #{Exception.message(e)}")
end

# decode [● stateful]
# Decode a file; input and output are binary files.
IO.puts("Testing decode...")

try do
  result = SnakeBridge.Base64.decode(%{input: "test", output: "test"})
  IO.puts("  ✓ decode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ decode: #{Exception.message(e)}")
end

# encode [● stateful]
# Encode a file; input and output are binary files.
IO.puts("Testing encode...")

try do
  result = SnakeBridge.Base64.encode(%{input: "test", output: "test"})
  IO.puts("  ✓ encode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ encode: #{Exception.message(e)}")
end

# main [● stateful]
# Small main program
IO.puts("Testing main...")

try do
  result = SnakeBridge.Base64.main()
  IO.puts("  ✓ main: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ main: #{Exception.message(e)}")
end

# urlsafe_b64decode [● stateful]
# Decode bytes using the URL- and filesystem-safe Base64 alphabet.
IO.puts("Testing urlsafe_b64decode...")

try do
  result = SnakeBridge.Base64.urlsafe_b64decode(%{s: "SGVsbG8="})
  IO.puts("  ✓ urlsafe_b64decode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ urlsafe_b64decode: #{Exception.message(e)}")
end

# urlsafe_b64encode [● stateful]
# Encode bytes using the URL- and filesystem-safe Base64 alphabet.
IO.puts("Testing urlsafe_b64encode...")

try do
  result = SnakeBridge.Base64.urlsafe_b64encode(%{s: <<72, 101, 108, 108, 111>>})
  IO.puts("  ✓ urlsafe_b64encode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ urlsafe_b64encode: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
