# stateless_examples.exs
# Auto-generated examples for SnakeBridge.Difflib
# Run with: mix run examples/generated/difflib/stateless_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Difflib Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# IS_CHARACTER_JUNK [○ stateless]
# Return True for ignorable character: iff `ch` is a space or tab.
IO.puts("Testing IS_CHARACTER_JUNK...")

try do
  result = SnakeBridge.Difflib."IS_CHARACTER_JUNK"(%{ch: "test"})
  IO.puts("  ✓ IS_CHARACTER_JUNK: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ IS_CHARACTER_JUNK: #{Exception.message(e)}")
end

# IS_LINE_JUNK [○ stateless]
# Return True for ignorable line: iff `line` is blank or contains a sing
IO.puts("Testing IS_LINE_JUNK...")

try do
  result = SnakeBridge.Difflib."IS_LINE_JUNK"(%{line: "test"})
  IO.puts("  ✓ IS_LINE_JUNK: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ IS_LINE_JUNK: #{Exception.message(e)}")
end

# ndiff [○ stateless]
# Compare `a` and `b` (lists of strings); return a `Differ`-style delta.
IO.puts("Testing ndiff...")

try do
  result = SnakeBridge.Difflib.ndiff(%{a: "test", b: "test"})
  IO.puts("  ✓ ndiff: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ ndiff: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
