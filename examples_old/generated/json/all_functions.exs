# all_functions.exs
# Complete function reference for SnakeBridge.Json
# Run with: mix run examples/generated/json/all_functions.exs

Application.ensure_all_started(:snakebridge)
Process.sleep(1000)

# All available functions: {name, arity, stateless?}
functions = [
  {"detect_encoding", 1, :stateless},
  {"dump", 12, :stateful},
  {"dumps", 11, :stateless},
  {"load", 8, :stateful},
  {"loads", 8, :stateless}
]

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Json - All Functions")
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
