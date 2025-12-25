# stateful_examples.exs
# Auto-generated examples for SnakeBridge.Statistics
# Run with: mix run examples/generated/statistics/stateful_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Statistics Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# pvariance [● stateful]
# Return the population variance of ``data``.
IO.puts("Testing pvariance...")

try do
  result = SnakeBridge.Statistics.pvariance(%{data: [1, 2, 3]})
  IO.puts("  ✓ pvariance: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ pvariance: #{Exception.message(e)}")
end

# variance [● stateful]
# Return the sample variance of data.
IO.puts("Testing variance...")

try do
  result = SnakeBridge.Statistics.variance(%{data: [1, 2, 3]})
  IO.puts("  ✓ variance: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ variance: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
