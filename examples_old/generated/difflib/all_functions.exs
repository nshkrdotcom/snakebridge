# all_functions.exs
# Complete function reference for SnakeBridge.Difflib
# Run with: mix run examples/generated/difflib/all_functions.exs

Application.ensure_all_started(:snakebridge)
Process.sleep(1000)

# All available functions: {name, arity, stateless?}
functions = [
  {"IS_CHARACTER_JUNK", 2, :stateless},
  {"IS_LINE_JUNK", 2, :stateless},
  {"context_diff", 8, :stateful},
  {"diff_bytes", 9, :stateful},
  {"get_close_matches", 4, :stateful},
  {"ndiff", 4, :stateless},
  {"restore", 2, :stateful},
  {"unified_diff", 8, :stateful}
]

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Difflib - All Functions")
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
