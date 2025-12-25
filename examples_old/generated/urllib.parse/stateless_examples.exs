# stateless_examples.exs
# Auto-generated examples for SnakeBridge.UrllibParse
# Run with: mix run examples/generated/urllib.parse/stateless_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.UrllibParse Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# clear_cache [○ stateless]
# Clear internal performance caches. Undocumented; some tests want it.
IO.puts("Testing clear_cache...")

try do
  result = SnakeBridge.UrllibParse.clear_cache()
  IO.puts("  ✓ clear_cache: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ clear_cache: #{Exception.message(e)}")
end

# namedtuple [○ stateless]
# Returns a new subclass of tuple with named fields.
IO.puts("Testing namedtuple...")

try do
  result = SnakeBridge.UrllibParse.namedtuple(%{typename: "test", field_names: "test"})
  IO.puts("  ✓ namedtuple: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ namedtuple: #{Exception.message(e)}")
end

# quote_from_bytes [○ stateless]
# Like quote(), but accepts a bytes object rather than a str, and does
IO.puts("Testing quote_from_bytes...")

try do
  result = SnakeBridge.UrllibParse.quote_from_bytes(%{bs: <<72, 101, 108, 108, 111>>})
  IO.puts("  ✓ quote_from_bytes: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ quote_from_bytes: #{Exception.message(e)}")
end

# quote_plus [○ stateless]
# Like quote(), but also replace ' ' with '+', as required for quoting
IO.puts("Testing quote_plus...")

try do
  result = SnakeBridge.UrllibParse.quote_plus(%{string: "test"})
  IO.puts("  ✓ quote_plus: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ quote_plus: #{Exception.message(e)}")
end

# splitattr [○ stateless]
# 
IO.puts("Testing splitattr...")

try do
  result = SnakeBridge.UrllibParse.splitattr(%{url: "https://example.com"})
  IO.puts("  ✓ splitattr: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ splitattr: #{Exception.message(e)}")
end

# splithost [○ stateless]
# 
IO.puts("Testing splithost...")

try do
  result = SnakeBridge.UrllibParse.splithost(%{url: "https://example.com"})
  IO.puts("  ✓ splithost: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ splithost: #{Exception.message(e)}")
end

# splitnport [○ stateless]
# 
IO.puts("Testing splitnport...")

try do
  result = SnakeBridge.UrllibParse.splitnport(%{host: "test"})
  IO.puts("  ✓ splitnport: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ splitnport: #{Exception.message(e)}")
end

# splitpasswd [○ stateless]
# 
IO.puts("Testing splitpasswd...")

try do
  result = SnakeBridge.UrllibParse.splitpasswd(%{user: "test"})
  IO.puts("  ✓ splitpasswd: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ splitpasswd: #{Exception.message(e)}")
end

# splitport [○ stateless]
# 
IO.puts("Testing splitport...")

try do
  result = SnakeBridge.UrllibParse.splitport(%{host: "test"})
  IO.puts("  ✓ splitport: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ splitport: #{Exception.message(e)}")
end

# splittag [○ stateless]
# 
IO.puts("Testing splittag...")

try do
  result = SnakeBridge.UrllibParse.splittag(%{url: "https://example.com"})
  IO.puts("  ✓ splittag: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ splittag: #{Exception.message(e)}")
end

# splittype [○ stateless]
# 
IO.puts("Testing splittype...")

try do
  result = SnakeBridge.UrllibParse.splittype(%{url: "https://example.com"})
  IO.puts("  ✓ splittype: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ splittype: #{Exception.message(e)}")
end

# splituser [○ stateless]
# 
IO.puts("Testing splituser...")

try do
  result = SnakeBridge.UrllibParse.splituser(%{host: "test"})
  IO.puts("  ✓ splituser: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ splituser: #{Exception.message(e)}")
end

# splitvalue [○ stateless]
# 
IO.puts("Testing splitvalue...")

try do
  result = SnakeBridge.UrllibParse.splitvalue(%{attr: "test"})
  IO.puts("  ✓ splitvalue: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ splitvalue: #{Exception.message(e)}")
end

# to_bytes [○ stateless]
# 
IO.puts("Testing to_bytes...")

try do
  result = SnakeBridge.UrllibParse.to_bytes(%{url: "https://example.com"})
  IO.puts("  ✓ to_bytes: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ to_bytes: #{Exception.message(e)}")
end

# unquote [○ stateless]
# Replace %xx escapes by their single-character equivalent. The optional
IO.puts("Testing unquote...")

try do
  result = SnakeBridge.UrllibParse.unquote(%{string: "test"})
  IO.puts("  ✓ unquote: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ unquote: #{Exception.message(e)}")
end

# unquote_plus [○ stateless]
# Like unquote(), but also replace plus signs by spaces, as required for
IO.puts("Testing unquote_plus...")

try do
  result = SnakeBridge.UrllibParse.unquote_plus(%{string: "test"})
  IO.puts("  ✓ unquote_plus: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ unquote_plus: #{Exception.message(e)}")
end

# unquote_to_bytes [○ stateless]
# unquote_to_bytes('abc%20def') -> b'abc def'.
IO.puts("Testing unquote_to_bytes...")

try do
  result = SnakeBridge.UrllibParse.unquote_to_bytes(%{string: "test"})
  IO.puts("  ✓ unquote_to_bytes: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ unquote_to_bytes: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
