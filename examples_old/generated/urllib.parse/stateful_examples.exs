# stateful_examples.exs
# Auto-generated examples for SnakeBridge.UrllibParse
# Run with: mix run examples/generated/urllib.parse/stateful_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.UrllibParse Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# parse_qs [● stateful]
# Parse a query given as a string argument.
IO.puts("Testing parse_qs...")

try do
  result = SnakeBridge.UrllibParse.parse_qs(%{qs: "test"})
  IO.puts("  ✓ parse_qs: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ parse_qs: #{Exception.message(e)}")
end

# parse_qsl [● stateful]
# Parse a query given as a string argument.
IO.puts("Testing parse_qsl...")

try do
  result = SnakeBridge.UrllibParse.parse_qsl(%{qs: "test"})
  IO.puts("  ✓ parse_qsl: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ parse_qsl: #{Exception.message(e)}")
end

# quote [● stateful]
# quote('abc def') -> 'abc%20def'
IO.puts("Testing quote...")

try do
  result = SnakeBridge.UrllibParse.quote(%{string: "test"})
  IO.puts("  ✓ quote: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ quote: #{Exception.message(e)}")
end

# splitquery [● stateful]
# 
IO.puts("Testing splitquery...")

try do
  result = SnakeBridge.UrllibParse.splitquery(%{url: "https://example.com"})
  IO.puts("  ✓ splitquery: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ splitquery: #{Exception.message(e)}")
end

# unwrap [● stateful]
# Transform a string like '<URL:scheme://host/path>' into 'scheme://host
IO.puts("Testing unwrap...")

try do
  result = SnakeBridge.UrllibParse.unwrap(%{url: "https://example.com"})
  IO.puts("  ✓ unwrap: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ unwrap: #{Exception.message(e)}")
end

# urldefrag [● stateful]
# Removes any existing fragment from URL.
IO.puts("Testing urldefrag...")

try do
  result = SnakeBridge.UrllibParse.urldefrag(%{url: "https://example.com"})
  IO.puts("  ✓ urldefrag: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ urldefrag: #{Exception.message(e)}")
end

# urlencode [● stateful]
# Encode a dict or sequence of two-element tuples into a URL query strin
IO.puts("Testing urlencode...")

try do
  result = SnakeBridge.UrllibParse.urlencode(%{query: "test"})
  IO.puts("  ✓ urlencode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ urlencode: #{Exception.message(e)}")
end

# urljoin [● stateful]
# Join a base URL and a possibly relative URL to form an absolute
IO.puts("Testing urljoin...")

try do
  result = SnakeBridge.UrllibParse.urljoin(%{base: "test", url: "https://example.com"})
  IO.puts("  ✓ urljoin: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ urljoin: #{Exception.message(e)}")
end

# urlparse [● stateful]
# Parse a URL into 6 components:
IO.puts("Testing urlparse...")

try do
  result = SnakeBridge.UrllibParse.urlparse(%{url: "https://example.com"})
  IO.puts("  ✓ urlparse: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ urlparse: #{Exception.message(e)}")
end

# urlunparse [● stateful]
# Put a parsed URL back together again.  This may result in a
IO.puts("Testing urlunparse...")

try do
  result = SnakeBridge.UrllibParse.urlunparse(%{components: "test"})
  IO.puts("  ✓ urlunparse: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ urlunparse: #{Exception.message(e)}")
end

# urlunsplit [● stateful]
# Combine the elements of a tuple as returned by urlsplit() into a
IO.puts("Testing urlunsplit...")

try do
  result = SnakeBridge.UrllibParse.urlunsplit(%{components: "test"})
  IO.puts("  ✓ urlunsplit: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ urlunsplit: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
