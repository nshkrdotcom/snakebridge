# stateless_examples.exs
# Auto-generated examples for SnakeBridge.Re
# Run with: mix run examples/generated/re/stateless_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Re Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# escape [○ stateless]
# Escape special characters in a string.
IO.puts("Testing escape...")

try do
  result = SnakeBridge.Re.escape(%{pattern: ".*"})
  IO.puts("  ✓ escape: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ escape: #{Exception.message(e)}")
end

# findall [○ stateless]
# Return a list of all non-overlapping matches in the string.
IO.puts("Testing findall...")

try do
  result = SnakeBridge.Re.findall(%{pattern: ".*", string: "test"})
  IO.puts("  ✓ findall: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ findall: #{Exception.message(e)}")
end

# finditer [○ stateless]
# Return an iterator over all non-overlapping matches in the
IO.puts("Testing finditer...")

try do
  result = SnakeBridge.Re.finditer(%{pattern: ".*", string: "test"})
  IO.puts("  ✓ finditer: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ finditer: #{Exception.message(e)}")
end

# fullmatch [○ stateless]
# Try to apply the pattern to all of the string, returning
IO.puts("Testing fullmatch...")

try do
  result = SnakeBridge.Re.fullmatch(%{pattern: ".*", string: "test"})
  IO.puts("  ✓ fullmatch: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ fullmatch: #{Exception.message(e)}")
end

# match [○ stateless]
# Try to apply the pattern at the start of the string, returning
IO.puts("Testing match...")

try do
  result = SnakeBridge.Re.match(%{pattern: ".*", string: "test"})
  IO.puts("  ✓ match: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ match: #{Exception.message(e)}")
end

# purge [○ stateless]
# Clear the regular expression caches
IO.puts("Testing purge...")

try do
  result = SnakeBridge.Re.purge()
  IO.puts("  ✓ purge: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ purge: #{Exception.message(e)}")
end

# search [○ stateless]
# Scan through string looking for a match to the pattern, returning
IO.puts("Testing search...")

try do
  result = SnakeBridge.Re.search(%{pattern: ".*", string: "test"})
  IO.puts("  ✓ search: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ search: #{Exception.message(e)}")
end

# split [○ stateless]
# Split the source string by the occurrences of the pattern,
IO.puts("Testing split...")

try do
  result = SnakeBridge.Re.split(%{pattern: ".*", string: "test"})
  IO.puts("  ✓ split: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ split: #{Exception.message(e)}")
end

# sub [○ stateless]
# Return the string obtained by replacing the leftmost
IO.puts("Testing sub...")

try do
  result = SnakeBridge.Re.sub(%{pattern: ".*", repl: "test", string: "test"})
  IO.puts("  ✓ sub: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ sub: #{Exception.message(e)}")
end

# subn [○ stateless]
# Return a 2-tuple containing (new_string, number).
IO.puts("Testing subn...")

try do
  result = SnakeBridge.Re.subn(%{pattern: ".*", repl: "test", string: "test"})
  IO.puts("  ✓ subn: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ subn: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
