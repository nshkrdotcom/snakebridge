# all_functions.exs
# Complete function reference for SnakeBridge.Re
# Run with: mix run examples/generated/re/all_functions.exs

Application.ensure_all_started(:snakebridge)
Process.sleep(1000)

# All available functions: {name, arity, stateless?}
functions = [
  {"compile", 2, :stateful},
  {"escape", 1, :stateless},
  {"findall", 3, :stateless},
  {"finditer", 3, :stateless},
  {"fullmatch", 3, :stateless},
  {"match", 3, :stateless},
  {"purge", 0, :stateless},
  {"search", 3, :stateless},
  {"split", 4, :stateless},
  {"sub", 5, :stateless},
  {"subn", 5, :stateless},
  {"template", 2, :stateful}
]

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Re - All Functions")
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
