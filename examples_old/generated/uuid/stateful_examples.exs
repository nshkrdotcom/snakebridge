# stateful_examples.exs
# Auto-generated examples for SnakeBridge.Uuid
# Run with: mix run examples/generated/uuid/stateful_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Uuid Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# main [● stateful]
# Run the uuid command line interface.
IO.puts("Testing main...")

try do
  result = SnakeBridge.Uuid.main()
  IO.puts("  ✓ main: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ main: #{Exception.message(e)}")
end

# uuid1 [● stateful]
# Generate a UUID from a host ID, sequence number, and the current time.
IO.puts("Testing uuid1...")

try do
  result = SnakeBridge.Uuid.uuid1()
  IO.puts("  ✓ uuid1: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ uuid1: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
