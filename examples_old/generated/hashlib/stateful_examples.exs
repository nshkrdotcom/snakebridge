# stateful_examples.exs
# Auto-generated examples for SnakeBridge.Hashlib
# Run with: mix run examples/generated/hashlib/stateful_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Hashlib Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# file_digest [● stateful]
# Hash the contents of a file-like object. Returns a digest object.
IO.puts("Testing file_digest...")

try do
  result = SnakeBridge.Hashlib.file_digest(%{fileobj: "/tmp/test", digest: "test"})
  IO.puts("  ✓ file_digest: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ file_digest: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
