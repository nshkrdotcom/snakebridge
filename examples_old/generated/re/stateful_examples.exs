# stateful_examples.exs
# Auto-generated examples for SnakeBridge.Re
# Run with: mix run examples/generated/re/stateful_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Re Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# compile [● stateful]
# Compile a regular expression pattern, returning a Pattern object.
IO.puts("Testing compile...")

try do
  result = SnakeBridge.Re.compile(%{pattern: ".*"})
  IO.puts("  ✓ compile: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ compile: #{Exception.message(e)}")
end

# template [● stateful]
# Compile a template pattern, returning a Pattern object, deprecated
IO.puts("Testing template...")

try do
  result = SnakeBridge.Re.template(%{pattern: ".*"})
  IO.puts("  ✓ template: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ template: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
