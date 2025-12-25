# stateless_examples.exs
# Auto-generated examples for SnakeBridge.Sympy
# Run with: mix run examples/generated/sympy/stateless_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Sympy Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# fps [○ stateless]
# Generates Formal Power Series of ``f``.
IO.puts("Testing fps...")

try do
  result = SnakeBridge.Sympy.fps(%{f: "test"})
  IO.puts("  ✓ fps: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ fps: #{Exception.message(e)}")
end

# pquo [○ stateless]
# Compute polynomial pseudo-quotient of ``f`` and ``g``.
IO.puts("Testing pquo...")

try do
  result = SnakeBridge.Sympy.pquo(%{f: "test", g: "test"})
  IO.puts("  ✓ pquo: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ pquo: #{Exception.message(e)}")
end

# print_rcode [○ stateless]
# Prints R representation of the given expression.
IO.puts("Testing print_rcode...")

try do
  result = SnakeBridge.Sympy.print_rcode(%{expr: "test"})
  IO.puts("  ✓ print_rcode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ print_rcode: #{Exception.message(e)}")
end

# randMatrix [○ stateless]
# Create random matrix with dimensions ``r`` x ``c``. If ``c`` is omitte
IO.puts("Testing randMatrix...")

try do
  result = SnakeBridge.Sympy.randMatrix(%{r: "test"})
  IO.puts("  ✓ randMatrix: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ randMatrix: #{Exception.message(e)}")
end

# bottom_up [○ stateless]
# Apply ``F`` to all expressions in an expression tree from the
IO.puts("Testing bottom_up...")

try do
  result = SnakeBridge.Sympy.bottom_up(%{rv: "test", F: "test"})
  IO.puts("  ✓ bottom_up: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ bottom_up: #{Exception.message(e)}")
end

# total_degree [○ stateless]
# Return the total_degree of ``f`` in the given variables.
IO.puts("Testing total_degree...")

try do
  result = SnakeBridge.Sympy.total_degree(%{f: "test"})
  IO.puts("  ✓ total_degree: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ total_degree: #{Exception.message(e)}")
end

# ratsimp [○ stateless]
# Put an expression over a common denominator, cancel and reduce.
IO.puts("Testing ratsimp...")

try do
  result = SnakeBridge.Sympy.ratsimp(%{expr: "test"})
  IO.puts("  ✓ ratsimp: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ ratsimp: #{Exception.message(e)}")
end

# sturm [○ stateless]
# Compute Sturm sequence of ``f``.
IO.puts("Testing sturm...")

try do
  result = SnakeBridge.Sympy.sturm(%{f: "test"})
  IO.puts("  ✓ sturm: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ sturm: #{Exception.message(e)}")
end

# cxxcode [○ stateless]
# C++ equivalent of :func:`~.ccode`. 
IO.puts("Testing cxxcode...")

try do
  result = SnakeBridge.Sympy.cxxcode(%{expr: "test"})
  IO.puts("  ✓ cxxcode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ cxxcode: #{Exception.message(e)}")
end

# count_ops [○ stateless]
# Return a representation (integer or expression) of the operations in e
IO.puts("Testing count_ops...")

try do
  result = SnakeBridge.Sympy.count_ops(%{expr: "test"})
  IO.puts("  ✓ count_ops: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ count_ops: #{Exception.message(e)}")
end

# arity [○ stateless]
# Return the arity of the function if it is known, else None.
IO.puts("Testing arity...")

try do
  result = SnakeBridge.Sympy.arity(%{cls: "test"})
  IO.puts("  ✓ arity: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ arity: #{Exception.message(e)}")
end

# invert [○ stateless]
# Invert ``f`` modulo ``g`` when possible.
IO.puts("Testing invert...")

try do
  result = SnakeBridge.Sympy.invert(%{f: "test", g: "test"})
  IO.puts("  ✓ invert: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ invert: #{Exception.message(e)}")
end

# primitive_root [○ stateless]
# Returns a primitive root of ``p`` or None.
IO.puts("Testing primitive_root...")

try do
  result = SnakeBridge.Sympy.primitive_root(%{p: "test"})
  IO.puts("  ✓ primitive_root: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ primitive_root: #{Exception.message(e)}")
end

# continued_fraction_convergents [○ stateless]
# Return an iterator over the convergents of a continued fraction (cf).
IO.puts("Testing continued_fraction_convergents...")

try do
  result = SnakeBridge.Sympy.continued_fraction_convergents(%{cf: "test"})
  IO.puts("  ✓ continued_fraction_convergents: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ continued_fraction_convergents: #{Exception.message(e)}")
end

# rootof [○ stateless]
# An indexed root of a univariate polynomial.
IO.puts("Testing rootof...")

try do
  result = SnakeBridge.Sympy.rootof(%{f: "test", x: 10})
  IO.puts("  ✓ rootof: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ rootof: #{Exception.message(e)}")
end

# differentiate_finite [○ stateless]
# Differentiate expr and replace Derivatives with finite differences.
IO.puts("Testing differentiate_finite...")

try do
  result = SnakeBridge.Sympy.differentiate_finite(%{expr: "test"})
  IO.puts("  ✓ differentiate_finite: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ differentiate_finite: #{Exception.message(e)}")
end

# proper_divisors [○ stateless]
# Return all divisors of n except n, sorted by default.
IO.puts("Testing proper_divisors...")

try do
  result = SnakeBridge.Sympy.proper_divisors(%{n: 10})
  IO.puts("  ✓ proper_divisors: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ proper_divisors: #{Exception.message(e)}")
end

# list2numpy [○ stateless]
# Converts Python list of SymPy expressions to a NumPy array.
IO.puts("Testing list2numpy...")

try do
  result = SnakeBridge.Sympy.list2numpy(%{l: "test"})
  IO.puts("  ✓ list2numpy: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ list2numpy: #{Exception.message(e)}")
end

# reshape [○ stateless]
# Reshape the sequence according to the template in ``how``.
IO.puts("Testing reshape...")

try do
  result = SnakeBridge.Sympy.reshape(%{seq: [1, 2, 3], how: "test"})
  IO.puts("  ✓ reshape: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ reshape: #{Exception.message(e)}")
end

# swinnerton_dyer_poly [○ stateless]
# Generates n-th Swinnerton-Dyer polynomial in `x`.
IO.puts("Testing swinnerton_dyer_poly...")

try do
  result = SnakeBridge.Sympy.swinnerton_dyer_poly(%{n: 10})
  IO.puts("  ✓ swinnerton_dyer_poly: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ swinnerton_dyer_poly: #{Exception.message(e)}")
end

# groebner [○ stateless]
# Computes the reduced Groebner basis for a set of polynomials.
IO.puts("Testing groebner...")

try do
  result = SnakeBridge.Sympy.groebner(%{F: "test"})
  IO.puts("  ✓ groebner: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ groebner: #{Exception.message(e)}")
end

# check_assumptions [○ stateless]
# Checks whether assumptions of ``expr`` match the T/F assumptions
IO.puts("Testing check_assumptions...")

try do
  result = SnakeBridge.Sympy.check_assumptions(%{expr: "test"})
  IO.puts("  ✓ check_assumptions: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ check_assumptions: #{Exception.message(e)}")
end

# checkpdesol [○ stateless]
# Checks if the given solution satisfies the partial differential
IO.puts("Testing checkpdesol...")

try do
  result = SnakeBridge.Sympy.checkpdesol(%{pde: "test", sol: "test"})
  IO.puts("  ✓ checkpdesol: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ checkpdesol: #{Exception.message(e)}")
end

# gff_list [○ stateless]
# Compute a list of greatest factorial factors of ``f``.
IO.puts("Testing gff_list...")

try do
  result = SnakeBridge.Sympy.gff_list(%{f: "test"})
  IO.puts("  ✓ gff_list: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ gff_list: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
