# all_functions.exs
# Complete function reference for SnakeBridge.Numpy
# Run with: mix run examples/generated/numpy/all_functions.exs

Application.ensure_all_started(:snakebridge)
Process.sleep(1000)

# All available functions: {name, arity, stateless?}
functions = [
  {"load", 6, :stateful},
  {"broadcast_shapes", 1, :stateless},
  {"isfortran", 1, :stateful},
  {"isdtype", 2, :stateless},
  {"trapz", 4, :stateless},
  {"kaiser", 2, :stateful},
  {"row_stack", 3, :stateful},
  {"get_printoptions", 0, :stateless},
  {"show_runtime", 0, :stateful},
  {"full", 6, :stateful},
  {"ones", 5, :stateful},
  {"tril_indices", 3, :stateless},
  {"mask_indices", 3, :stateless},
  {"loadtxt", 13, :stateful},
  {"require", 4, :stateful},
  {"mintypecode", 3, :stateless},
  {"show_config", 1, :stateful},
  {"isscalar", 1, :stateful},
  {"asmatrix", 2, :stateful},
  {"seterrcall", 1, :stateful},
  {"getbufsize", 0, :stateless},
  {"setbufsize", 1, :stateless},
  {"info", 4, :stateful},
  {"hanning", 1, :stateful},
  {"geterr", 0, :stateless},
  {"base_repr", 3, :stateless},
  {"identity", 3, :stateless},
  {"binary_repr", 2, :stateful},
  {"triu_indices", 3, :stateless},
  {"asarray_chkfinite", 3, :stateful},
  {"format_float_scientific", 8, :stateless},
  {"bmat", 3, :stateful},
  {"geterrcall", 0, :stateless},
  {"iterable", 1, :stateless},
  {"format_float_positional", 9, :stateless},
  {"fromregex", 4, :stateful},
  {"indices", 3, :stateless},
  {"typename", 1, :stateless},
  {"seterr", 5, :stateful},
  {"set_printoptions", 12, :stateful},
  {"tri", 5, :stateless},
  {"printoptions", 2, :stateful},
  {"hamming", 1, :stateful},
  {"diag_indices", 2, :stateless},
  {"genfromtxt", 25, :stateful},
  {"eye", 7, :stateful},
  {"bartlett", 1, :stateful},
  {"blackman", 1, :stateful},
  {"get_include", 0, :stateful},
  {"fromfunction", 5, :stateful}
]

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Numpy - All Functions")
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
