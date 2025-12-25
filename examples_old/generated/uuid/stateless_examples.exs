# stateless_examples.exs
# Auto-generated examples for SnakeBridge.Uuid
# Run with: mix run examples/generated/uuid/stateless_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Uuid Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# getnode [○ stateless]
# Get the hardware address as a 48-bit positive integer.
IO.puts("Testing getnode...")

try do
  result = SnakeBridge.Uuid.getnode()
  IO.puts("  ✓ getnode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ getnode: #{Exception.message(e)}")
end

# uuid3 [○ stateless]
# Generate a UUID from the MD5 hash of a namespace UUID and a name.
IO.puts("Testing uuid3...")

try do
  result = SnakeBridge.Uuid.uuid3(%{namespace: "test", name: "md5"})
  IO.puts("  ✓ uuid3: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ uuid3: #{Exception.message(e)}")
end

# uuid4 [○ stateless]
# Generate a random UUID.
IO.puts("Testing uuid4...")

try do
  result = SnakeBridge.Uuid.uuid4()
  IO.puts("  ✓ uuid4: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ uuid4: #{Exception.message(e)}")
end

# uuid5 [○ stateless]
# Generate a UUID from the SHA-1 hash of a namespace UUID and a name.
IO.puts("Testing uuid5...")

try do
  result = SnakeBridge.Uuid.uuid5(%{namespace: "test", name: "md5"})
  IO.puts("  ✓ uuid5: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ uuid5: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
