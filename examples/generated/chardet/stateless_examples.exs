# stateless_examples.exs
# Auto-generated examples for SnakeBridge.Chardet
# Run with: mix run examples/generated/chardet/stateless_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Chardet Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# detect [○ stateless]
# Detect the encoding of the given byte string.
IO.puts("Testing detect...")

try do
  result = SnakeBridge.Chardet.detect(%{byte_str: <<72, 101, 108, 108, 111>>})
  IO.puts("  ✓ detect: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ detect: #{Exception.message(e)}")
end

# detect_all [○ stateless]
# Detect all the possible encodings of the given byte string.
IO.puts("Testing detect_all...")

try do
  result = SnakeBridge.Chardet.detect_all(%{byte_str: <<72, 101, 108, 108, 111>>})
  IO.puts("  ✓ detect_all: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ detect_all: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
