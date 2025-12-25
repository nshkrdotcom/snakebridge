# all_functions.exs
# Complete function reference for SnakeBridge.Base64
# Run with: mix run examples/generated/base64/all_functions.exs

Application.ensure_all_started(:snakebridge)
Process.sleep(1000)

# All available functions: {name, arity, stateless?}
functions = [
  {"a85decode", 4, :stateless},
  {"a85encode", 5, :stateless},
  {"b16decode", 2, :stateless},
  {"b16encode", 1, :stateless},
  {"b32decode", 3, :stateless},
  {"b32encode", 1, :stateless},
  {"b32hexdecode", 2, :stateless},
  {"b32hexencode", 1, :stateless},
  {"b64decode", 3, :stateful},
  {"b64encode", 2, :stateful},
  {"b85decode", 1, :stateless},
  {"b85encode", 2, :stateless},
  {"decode", 2, :stateful},
  {"decodebytes", 1, :stateless},
  {"encode", 2, :stateful},
  {"encodebytes", 1, :stateless},
  {"main", 0, :stateful},
  {"standard_b64decode", 1, :stateless},
  {"standard_b64encode", 1, :stateless},
  {"urlsafe_b64decode", 1, :stateful},
  {"urlsafe_b64encode", 1, :stateful}
]

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Base64 - All Functions")
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
