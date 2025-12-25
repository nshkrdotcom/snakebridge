# stateful_examples.exs
# Auto-generated examples for SnakeBridge.Textwrap
# Run with: mix run examples/generated/textwrap/stateful_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Textwrap Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# dedent [● stateful]
# Remove any common leading whitespace from every line in `text`.
IO.puts("Testing dedent...")

try do
  result = SnakeBridge.Textwrap.dedent(%{text: "test"})
  IO.puts("  ✓ dedent: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ dedent: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
