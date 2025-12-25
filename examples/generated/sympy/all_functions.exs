# all_functions.exs
# Complete function reference for SnakeBridge.Sympy
# Run with: mix run examples/generated/sympy/all_functions.exs

Application.ensure_all_started(:snakebridge)
Process.sleep(1000)

# All available functions: {name, arity, stateless?}
functions = [
  {"mathematica_code", 2, :stateful},
  {"factorint", 9, :stateful},
  {"sympify", 6, :stateful},
  {"solve_linear", 4, :stateful},
  {"tensorproduct", 1, :stateful},
  {"lambdify", 8, :stateful},
  {"is_strictly_decreasing", 3, :stateful},
  {"ifft", 2, :stateful},
  {"powsimp", 5, :stateful},
  {"fps", 8, :stateless},
  {"pquo", 4, :stateless},
  {"print_rcode", 2, :stateless},
  {"randMatrix", 8, :stateless},
  {"bottom_up", 4, :stateless},
  {"is_monotonic", 3, :stateful},
  {"total_degree", 2, :stateless},
  {"isprime", 1, :stateful},
  {"ratsimp", 1, :stateless},
  {"sturm", 3, :stateless},
  {"to_cnf", 3, :stateful},
  {"pycode", 2, :stateful},
  {"cxxcode", 4, :stateless},
  {"count_ops", 2, :stateless},
  {"real_roots", 4, :stateful},
  {"product", 2, :stateful},
  {"arity", 1, :stateless},
  {"jn_zeros", 4, :stateful},
  {"N", 3, :stateful},
  {"cbrt", 2, :stateful},
  {"npartitions", 2, :stateful},
  {"gammasimp", 1, :stateful},
  {"invert", 4, :stateless},
  {"get_indices", 1, :stateful},
  {"collect", 6, :stateful},
  {"epath", 5, :stateful},
  {"primitive_root", 2, :stateless},
  {"continued_fraction_convergents", 1, :stateless},
  {"rootof", 5, :stateless},
  {"differentiate_finite", 6, :stateless},
  {"roots", 12, :stateful},
  {"octave_code", 3, :stateful},
  {"proper_divisors", 2, :stateless},
  {"list2numpy", 2, :stateless},
  {"reshape", 2, :stateless},
  {"swinnerton_dyer_poly", 3, :stateless},
  {"groebner", 3, :stateless},
  {"diff", 3, :stateful},
  {"check_assumptions", 3, :stateless},
  {"checkpdesol", 4, :stateless},
  {"gff_list", 3, :stateless}
]

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Sympy - All Functions")
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
