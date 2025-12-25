# stateful_examples.exs
# Auto-generated examples for SnakeBridge.Requests
# Run with: mix run examples/generated/requests/stateful_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Requests Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# delete [● stateful]
# Sends a DELETE request.
IO.puts("Testing delete...")

try do
  result = SnakeBridge.Requests.delete(%{url: "https://example.com"})
  IO.puts("  ✓ delete: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ delete: #{Exception.message(e)}")
end

# get [● stateful]
# Sends a GET request.
IO.puts("Testing get...")

try do
  result = SnakeBridge.Requests.get(%{url: "https://example.com"})
  IO.puts("  ✓ get: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ get: #{Exception.message(e)}")
end

# head [● stateful]
# Sends a HEAD request.
IO.puts("Testing head...")

try do
  result = SnakeBridge.Requests.head(%{url: "https://example.com"})
  IO.puts("  ✓ head: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ head: #{Exception.message(e)}")
end

# options [● stateful]
# Sends an OPTIONS request.
IO.puts("Testing options...")

try do
  result = SnakeBridge.Requests.options(%{url: "https://example.com"})
  IO.puts("  ✓ options: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ options: #{Exception.message(e)}")
end

# patch [● stateful]
# Sends a PATCH request.
IO.puts("Testing patch...")

try do
  result = SnakeBridge.Requests.patch(%{url: "https://example.com"})
  IO.puts("  ✓ patch: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ patch: #{Exception.message(e)}")
end

# post [● stateful]
# Sends a POST request.
IO.puts("Testing post...")

try do
  result = SnakeBridge.Requests.post(%{url: "https://example.com"})
  IO.puts("  ✓ post: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ post: #{Exception.message(e)}")
end

# put [● stateful]
# Sends a PUT request.
IO.puts("Testing put...")

try do
  result = SnakeBridge.Requests.put(%{url: "https://example.com"})
  IO.puts("  ✓ put: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ put: #{Exception.message(e)}")
end

# request [● stateful]
# Constructs and sends a :class:`Request <Request>`.
IO.puts("Testing request...")

try do
  result = SnakeBridge.Requests.request(%{method: "GET", url: "https://example.com"})
  IO.puts("  ✓ request: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ request: #{Exception.message(e)}")
end

# session [● stateful]
# Returns a :class:`Session` for context-management.
IO.puts("Testing session...")

try do
  result = SnakeBridge.Requests.session()
  IO.puts("  ✓ session: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ session: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
