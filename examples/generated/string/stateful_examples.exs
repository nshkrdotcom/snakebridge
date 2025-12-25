# stateful_examples.exs
# Auto-generated examples for SnakeBridge.String
# Run with: mix run examples/generated/string/stateful_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.String Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# capwords [● stateful]
# capwords(s [,sep]) -> string
IO.puts("Testing capwords...")

try do
  result = SnakeBridge.String.capwords(%{s: "test"})
  IO.puts("  ✓ capwords: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ capwords: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
