# all_functions.exs
# Complete function reference for SnakeBridge.Requests
# Run with: mix run examples/generated/requests/all_functions.exs

Application.ensure_all_started(:snakebridge)
Process.sleep(1000)

# All available functions: {name, arity, stateless?}
functions = [
  {"check_compatibility", 3, :stateless},
  {"delete", 2, :stateful},
  {"get", 3, :stateful},
  {"head", 2, :stateful},
  {"options", 2, :stateful},
  {"patch", 3, :stateful},
  {"post", 4, :stateful},
  {"put", 3, :stateful},
  {"request", 3, :stateful},
  {"session", 0, :stateful}
]

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Requests - All Functions")
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
