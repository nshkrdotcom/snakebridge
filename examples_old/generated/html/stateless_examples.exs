# stateless_examples.exs
# Auto-generated examples for SnakeBridge.Html
# Run with: mix run examples/generated/html/stateless_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Html Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# escape [○ stateless]
# Replace special characters "&", "<" and ">" to HTML-safe sequences.
IO.puts("Testing escape...")

try do
  result = SnakeBridge.Html.escape(%{s: "test"})
  IO.puts("  ✓ escape: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ escape: #{Exception.message(e)}")
end

# unescape [○ stateless]
# Convert all named and numeric character references (e.g. &gt;, &#62;,
IO.puts("Testing unescape...")

try do
  result = SnakeBridge.Html.unescape(%{s: "test"})
  IO.puts("  ✓ unescape: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ unescape: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
