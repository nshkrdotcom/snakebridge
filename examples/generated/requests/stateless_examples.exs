# stateless_examples.exs
# Auto-generated examples for SnakeBridge.Requests
# Run with: mix run examples/generated/requests/stateless_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Requests Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# check_compatibility [○ stateless]
# 
IO.puts("Testing check_compatibility...")

try do
  result =
    SnakeBridge.Requests.check_compatibility(%{
      urllib3_version: "3.0.4",
      chardet_version: "3.0.4",
      charset_normalizer_version: "3.0.4"
    })

  IO.puts("  ✓ check_compatibility: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ check_compatibility: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
