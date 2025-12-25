# stateful_examples.exs
# Auto-generated examples for SnakeBridge.Difflib
# Run with: mix run examples/generated/difflib/stateful_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Difflib Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# context_diff [● stateful]
# Compare two sequences of lines; generate the delta as a context diff.
IO.puts("Testing context_diff...")

try do
  result = SnakeBridge.Difflib.context_diff(%{a: "test", b: "test"})
  IO.puts("  ✓ context_diff: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ context_diff: #{Exception.message(e)}")
end

# diff_bytes [● stateful]
# Compare `a` and `b`, two sequences of lines represented as bytes rathe
IO.puts("Testing diff_bytes...")

try do
  result =
    SnakeBridge.Difflib.diff_bytes(%{dfunc: "test", a: "test", b: <<72, 101, 108, 108, 111>>})

  IO.puts("  ✓ diff_bytes: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ diff_bytes: #{Exception.message(e)}")
end

# get_close_matches [● stateful]
# Use SequenceMatcher to return list of the best "good enough" matches.
IO.puts("Testing get_close_matches...")

try do
  result = SnakeBridge.Difflib.get_close_matches(%{word: "test", possibilities: "test"})
  IO.puts("  ✓ get_close_matches: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ get_close_matches: #{Exception.message(e)}")
end

# restore [● stateful]
# Generate one of the two sequences that generated a delta.
IO.puts("Testing restore...")

try do
  result = SnakeBridge.Difflib.restore(%{delta: "test", which: "test"})
  IO.puts("  ✓ restore: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ restore: #{Exception.message(e)}")
end

# unified_diff [● stateful]
# Compare two sequences of lines; generate the delta as a unified diff.
IO.puts("Testing unified_diff...")

try do
  result = SnakeBridge.Difflib.unified_diff(%{a: "test", b: "test"})
  IO.puts("  ✓ unified_diff: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ unified_diff: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
