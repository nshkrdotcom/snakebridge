# stateless_examples.exs
# Auto-generated examples for SnakeBridge.Hashlib
# Run with: mix run examples/generated/hashlib/stateless_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Hashlib Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# new [○ stateless]
# new(name, data=b'') - Return a new hashing object using the named algo
IO.puts("Testing new...")

try do
  result = SnakeBridge.Hashlib.new(%{name: "md5"})
  IO.puts("  ✓ new: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ new: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
