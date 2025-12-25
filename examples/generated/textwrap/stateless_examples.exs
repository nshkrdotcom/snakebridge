# stateless_examples.exs
# Auto-generated examples for SnakeBridge.Textwrap
# Run with: mix run examples/generated/textwrap/stateless_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Textwrap Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# fill [○ stateless]
# Fill a single paragraph of text, returning a new string.
IO.puts("Testing fill...")

try do
  result = SnakeBridge.Textwrap.fill(%{text: "test"})
  IO.puts("  ✓ fill: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ fill: #{Exception.message(e)}")
end

# indent [○ stateless]
# Adds 'prefix' to the beginning of selected lines in 'text'.
IO.puts("Testing indent...")

try do
  result = SnakeBridge.Textwrap.indent(%{text: "test", prefix: "test"})
  IO.puts("  ✓ indent: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ indent: #{Exception.message(e)}")
end

# shorten [○ stateless]
# Collapse and truncate the given text to fit in the given width.
IO.puts("Testing shorten...")

try do
  result = SnakeBridge.Textwrap.shorten(%{text: "test", width: 10})
  IO.puts("  ✓ shorten: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ shorten: #{Exception.message(e)}")
end

# wrap [○ stateless]
# Wrap a single paragraph of text, returning a list of wrapped lines.
IO.puts("Testing wrap...")

try do
  result = SnakeBridge.Textwrap.wrap(%{text: "test"})
  IO.puts("  ✓ wrap: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ wrap: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
