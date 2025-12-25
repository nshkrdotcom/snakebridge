# all_functions.exs
# Complete function reference for SnakeBridge.Hashlib
# Run with: mix run examples/generated/hashlib/all_functions.exs

Application.ensure_all_started(:snakebridge)
Process.sleep(1000)

# All available functions: {name, arity, stateless?}
functions = [
  {"file_digest", 3, :stateful},
  {"new", 3, :stateless}
]

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Hashlib - All Functions")
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
