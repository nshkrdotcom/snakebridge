# stateful_examples.exs
# Auto-generated examples for SnakeBridge.Json
# Run with: mix run examples/generated/json/stateful_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Json Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# dump [● stateful]
# Serialize ``obj`` as a JSON formatted stream to ``fp`` (a
IO.puts("Testing dump...")

try do
  result = SnakeBridge.Json.dump(%{obj: %{}, fp: "test"})
  IO.puts("  ✓ dump: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ dump: #{Exception.message(e)}")
end

# load [● stateful]
# Deserialize ``fp`` (a ``.read()``-supporting file-like object containi
IO.puts("Testing load...")

try do
  result = SnakeBridge.Json.load(%{fp: "test"})
  IO.puts("  ✓ load: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ load: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
