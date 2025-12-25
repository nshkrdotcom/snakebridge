# all_functions.exs
# Complete function reference for SnakeBridge.UrllibParse
# Run with: mix run examples/generated/urllib.parse/all_functions.exs

Application.ensure_all_started(:snakebridge)
Process.sleep(1000)

# All available functions: {name, arity, stateless?}
functions = [
  {"clear_cache", 0, :stateless},
  {"namedtuple", 5, :stateless},
  {"parse_qs", 7, :stateful},
  {"parse_qsl", 7, :stateful},
  {"quote", 4, :stateful},
  {"quote_from_bytes", 2, :stateless},
  {"quote_plus", 4, :stateless},
  {"splitattr", 1, :stateless},
  {"splithost", 1, :stateless},
  {"splitnport", 2, :stateless},
  {"splitpasswd", 1, :stateless},
  {"splitport", 1, :stateless},
  {"splitquery", 1, :stateful},
  {"splittag", 1, :stateless},
  {"splittype", 1, :stateless},
  {"splituser", 1, :stateless},
  {"splitvalue", 1, :stateless},
  {"to_bytes", 1, :stateless},
  {"unquote", 3, :stateless},
  {"unquote_plus", 3, :stateless},
  {"unquote_to_bytes", 1, :stateless},
  {"unwrap", 1, :stateful},
  {"urldefrag", 1, :stateful},
  {"urlencode", 6, :stateful},
  {"urljoin", 3, :stateful},
  {"urlparse", 3, :stateful},
  {"urlunparse", 1, :stateful},
  {"urlunsplit", 1, :stateful}
]

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.UrllibParse - All Functions")
IO.puts("=" |> String.duplicate(60))
IO.puts("")
IO.puts("Total functions: #{length(functions)}")
IO.puts("Stateless: #{Enum.count(functions, fn {_, _, s} -> s == :stateless end)}")
IO.puts("Stateful: #{Enum.count(functions, fn {_, _, s} -> s == :stateful end)}")
IO.puts("")

Enum.each(functions, fn {name, arity, stateless} ->
  marker = if stateless == :stateless, do: "○", else: "●"
  IO.puts("  #{marker} #{name}/#{arity}")
end)

IO.puts("")
IO.puts("Legend: ○ = stateless (pure), ● = stateful (may have side effects)")
