# stateful_examples.exs
# Auto-generated examples for SnakeBridge.Sympy
# Run with: mix run examples/generated/sympy/stateful_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Sympy Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# mathematica_code [● stateful]
# Converts an expr to a string of the Wolfram Mathematica code
IO.puts("Testing mathematica_code...")

try do
  result = SnakeBridge.Sympy.mathematica_code(%{expr: "test"})
  IO.puts("  ✓ mathematica_code: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ mathematica_code: #{Exception.message(e)}")
end

# factorint [● stateful]
# Given a positive integer ``n``, ``factorint(n)`` returns a dict contai
IO.puts("Testing factorint...")

try do
  result = SnakeBridge.Sympy.factorint(%{n: 10})
  IO.puts("  ✓ factorint: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ factorint: #{Exception.message(e)}")
end

# sympify [● stateful]
# Converts an arbitrary expression to a type that can be used inside Sym
IO.puts("Testing sympify...")

try do
  result = SnakeBridge.Sympy.sympify(%{a: "test"})
  IO.puts("  ✓ sympify: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ sympify: #{Exception.message(e)}")
end

# solve_linear [● stateful]
# Return a tuple derived from ``f = lhs - rhs`` that is one of
IO.puts("Testing solve_linear...")

try do
  result = SnakeBridge.Sympy.solve_linear(%{lhs: "test"})
  IO.puts("  ✓ solve_linear: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ solve_linear: #{Exception.message(e)}")
end

# tensorproduct [● stateful]
# Tensor product among scalars or array-like objects.
IO.puts("Testing tensorproduct...")

try do
  result = SnakeBridge.Sympy.tensorproduct()
  IO.puts("  ✓ tensorproduct: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ tensorproduct: #{Exception.message(e)}")
end

# lambdify [● stateful]
# Convert a SymPy expression into a function that allows for fast
IO.puts("Testing lambdify...")

try do
  result = SnakeBridge.Sympy.lambdify(%{expr: "test"})
  IO.puts("  ✓ lambdify: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ lambdify: #{Exception.message(e)}")
end

# is_strictly_decreasing [● stateful]
# Return whether the function is strictly decreasing in the given interv
IO.puts("Testing is_strictly_decreasing...")

try do
  result = SnakeBridge.Sympy.is_strictly_decreasing(%{expression: "test"})
  IO.puts("  ✓ is_strictly_decreasing: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ is_strictly_decreasing: #{Exception.message(e)}")
end

# ifft [● stateful]
# Performs the Discrete Fourier Transform (**DFT**) in the complex domai
IO.puts("Testing ifft...")

try do
  result = SnakeBridge.Sympy.ifft(%{seq: [1, 2, 3]})
  IO.puts("  ✓ ifft: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ ifft: #{Exception.message(e)}")
end

# powsimp [● stateful]
# Reduce expression by combining powers with similar bases and exponents
IO.puts("Testing powsimp...")

try do
  result = SnakeBridge.Sympy.powsimp(%{expr: "test"})
  IO.puts("  ✓ powsimp: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ powsimp: #{Exception.message(e)}")
end

# is_monotonic [● stateful]
# Return whether the function is monotonic in the given interval.
IO.puts("Testing is_monotonic...")

try do
  result = SnakeBridge.Sympy.is_monotonic(%{expression: "test"})
  IO.puts("  ✓ is_monotonic: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ is_monotonic: #{Exception.message(e)}")
end

# isprime [● stateful]
# Test if n is a prime number (True) or not (False). For n < 2^64 the
IO.puts("Testing isprime...")

try do
  result = SnakeBridge.Sympy.isprime(%{n: 10})
  IO.puts("  ✓ isprime: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ isprime: #{Exception.message(e)}")
end

# to_cnf [● stateful]
# Convert a propositional logical sentence ``expr`` to conjunctive norma
IO.puts("Testing to_cnf...")

try do
  result = SnakeBridge.Sympy.to_cnf(%{expr: "test"})
  IO.puts("  ✓ to_cnf: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ to_cnf: #{Exception.message(e)}")
end

# pycode [● stateful]
# Converts an expr to a string of Python code
IO.puts("Testing pycode...")

try do
  result = SnakeBridge.Sympy.pycode(%{expr: "test"})
  IO.puts("  ✓ pycode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ pycode: #{Exception.message(e)}")
end

# real_roots [● stateful]
# Returns the real roots of ``f`` with multiplicities.
IO.puts("Testing real_roots...")

try do
  result = SnakeBridge.Sympy.real_roots(%{f: "test"})
  IO.puts("  ✓ real_roots: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ real_roots: #{Exception.message(e)}")
end

# product [● stateful]
# Compute the product.
IO.puts("Testing product...")

try do
  result = SnakeBridge.Sympy.product()
  IO.puts("  ✓ product: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ product: #{Exception.message(e)}")
end

# jn_zeros [● stateful]
# Zeros of the spherical Bessel function of the first kind.
IO.puts("Testing jn_zeros...")

try do
  result = SnakeBridge.Sympy.jn_zeros(%{n: 10, k: 10})
  IO.puts("  ✓ jn_zeros: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ jn_zeros: #{Exception.message(e)}")
end

# N [● stateful]
# Calls x.evalf(n, \*\*options).
IO.puts("Testing N...")

try do
  result = SnakeBridge.Sympy."N"(%{x: 10})
  IO.puts("  ✓ N: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ N: #{Exception.message(e)}")
end

# cbrt [● stateful]
# Returns the principal cube root.
IO.puts("Testing cbrt...")

try do
  result = SnakeBridge.Sympy.cbrt(%{arg: "test"})
  IO.puts("  ✓ cbrt: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ cbrt: #{Exception.message(e)}")
end

# npartitions [● stateful]
# Calculate the partition function P(n), i.e. the number of ways that
IO.puts("Testing npartitions...")

try do
  result = SnakeBridge.Sympy.npartitions(%{n: 10})
  IO.puts("  ✓ npartitions: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ npartitions: #{Exception.message(e)}")
end

# gammasimp [● stateful]
# Simplify expressions with gamma functions.
IO.puts("Testing gammasimp...")

try do
  result = SnakeBridge.Sympy.gammasimp(%{expr: "test"})
  IO.puts("  ✓ gammasimp: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ gammasimp: #{Exception.message(e)}")
end

# get_indices [● stateful]
# Determine the outer indices of expression ``expr``
IO.puts("Testing get_indices...")

try do
  result = SnakeBridge.Sympy.get_indices(%{expr: "test"})
  IO.puts("  ✓ get_indices: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ get_indices: #{Exception.message(e)}")
end

# collect [● stateful]
# Collect additive terms of an expression.
IO.puts("Testing collect...")

try do
  result = SnakeBridge.Sympy.collect(%{expr: "test", syms: "test"})
  IO.puts("  ✓ collect: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ collect: #{Exception.message(e)}")
end

# epath [● stateful]
# Manipulate parts of an expression selected by a path.
IO.puts("Testing epath...")

try do
  result = SnakeBridge.Sympy.epath(%{path: "/tmp/test"})
  IO.puts("  ✓ epath: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ epath: #{Exception.message(e)}")
end

# roots [● stateful]
# Computes symbolic roots of a univariate polynomial.
IO.puts("Testing roots...")

try do
  result = SnakeBridge.Sympy.roots(%{f: "test"})
  IO.puts("  ✓ roots: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ roots: #{Exception.message(e)}")
end

# octave_code [● stateful]
# Converts `expr` to a string of Octave (or Matlab) code.
IO.puts("Testing octave_code...")

try do
  result = SnakeBridge.Sympy.octave_code(%{expr: "test"})
  IO.puts("  ✓ octave_code: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ octave_code: #{Exception.message(e)}")
end

# diff [● stateful]
# Differentiate f with respect to symbols.
IO.puts("Testing diff...")

try do
  result = SnakeBridge.Sympy.diff(%{f: "test"})
  IO.puts("  ✓ diff: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ diff: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
