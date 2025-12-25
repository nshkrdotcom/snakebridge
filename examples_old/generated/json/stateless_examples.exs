# stateless_examples.exs
# Auto-generated examples for SnakeBridge.Json
# Run with: mix run examples/generated/json/stateless_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Json Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# detect_encoding [○ stateless]
# 
IO.puts("Testing detect_encoding...")

try do
  result = SnakeBridge.Json.detect_encoding(%{b: <<72, 101, 108, 108, 111>>})
  IO.puts("  ✓ detect_encoding: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ detect_encoding: #{Exception.message(e)}")
end

# dumps [○ stateless]
# Serialize ``obj`` to a JSON formatted ``str``.
IO.puts("Testing dumps...")

try do
  result = SnakeBridge.Json.dumps(%{obj: %{}})
  IO.puts("  ✓ dumps: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ dumps: #{Exception.message(e)}")
end

# loads [○ stateless]
# Deserialize ``s`` (a ``str``, ``bytes`` or ``bytearray`` instance
IO.puts("Testing loads...")

try do
  result = SnakeBridge.Json.loads(%{s: "{\"hello\": \"world\"}"})
  IO.puts("  ✓ loads: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ loads: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
