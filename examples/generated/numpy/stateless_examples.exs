# stateless_examples.exs
# Auto-generated examples for SnakeBridge.Numpy
# Run with: mix run examples/generated/numpy/stateless_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Numpy Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# broadcast_shapes [○ stateless]
# Broadcast the input shapes into a single shape.
IO.puts("Testing broadcast_shapes...")

try do
  result = SnakeBridge.Numpy.broadcast_shapes()
  IO.puts("  ✓ broadcast_shapes: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ broadcast_shapes: #{Exception.message(e)}")
end

# isdtype [○ stateless]
# Determine if a provided dtype is of a specified data type ``kind``.
IO.puts("Testing isdtype...")

try do
  result = SnakeBridge.Numpy.isdtype(%{dtype: "int64", kind: "i"})
  IO.puts("  ✓ isdtype: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ isdtype: #{Exception.message(e)}")
end

# trapz [○ stateless]
# `trapz` is deprecated in NumPy 2.0.
IO.puts("Testing trapz...")

try do
  result = SnakeBridge.Numpy.trapz(%{y: [1, 2, 3]})
  IO.puts("  ✓ trapz: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ trapz: #{Exception.message(e)}")
end

# get_printoptions [○ stateless]
# Return the current print options.
IO.puts("Testing get_printoptions...")

try do
  result = SnakeBridge.Numpy.get_printoptions()
  IO.puts("  ✓ get_printoptions: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ get_printoptions: #{Exception.message(e)}")
end

# tril_indices [○ stateless]
# Return the indices for the lower-triangle of an (n, m) array.
IO.puts("Testing tril_indices...")

try do
  result = SnakeBridge.Numpy.tril_indices(%{n: 10})
  IO.puts("  ✓ tril_indices: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ tril_indices: #{Exception.message(e)}")
end

# mask_indices [○ stateless]
# Return the indices to access (n, n) arrays, given a masking function.
IO.puts("Testing mask_indices...")

try do
  result = SnakeBridge.Numpy.mask_indices(%{n: 10, mask_func: "test"})
  IO.puts("  ✓ mask_indices: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ mask_indices: #{Exception.message(e)}")
end

# mintypecode [○ stateless]
# Return the character for the minimum-size type to which given types ca
IO.puts("Testing mintypecode...")

try do
  result = SnakeBridge.Numpy.mintypecode(%{typechars: "test"})
  IO.puts("  ✓ mintypecode: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ mintypecode: #{Exception.message(e)}")
end

# getbufsize [○ stateless]
# Return the size of the buffer used in ufuncs.
IO.puts("Testing getbufsize...")

try do
  result = SnakeBridge.Numpy.getbufsize()
  IO.puts("  ✓ getbufsize: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ getbufsize: #{Exception.message(e)}")
end

# setbufsize [○ stateless]
# Set the size of the buffer used in ufuncs.
IO.puts("Testing setbufsize...")

try do
  result = SnakeBridge.Numpy.setbufsize(%{size: 10})
  IO.puts("  ✓ setbufsize: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ setbufsize: #{Exception.message(e)}")
end

# geterr [○ stateless]
# Get the current way of handling floating-point errors.
IO.puts("Testing geterr...")

try do
  result = SnakeBridge.Numpy.geterr()
  IO.puts("  ✓ geterr: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ geterr: #{Exception.message(e)}")
end

# base_repr [○ stateless]
# Return a string representation of a number in the given base system.
IO.puts("Testing base_repr...")

try do
  result = SnakeBridge.Numpy.base_repr(%{number: 10})
  IO.puts("  ✓ base_repr: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ base_repr: #{Exception.message(e)}")
end

# identity [○ stateless]
# Return the identity array.
IO.puts("Testing identity...")

try do
  result = SnakeBridge.Numpy.identity(%{n: 10})
  IO.puts("  ✓ identity: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ identity: #{Exception.message(e)}")
end

# triu_indices [○ stateless]
# Return the indices for the upper-triangle of an (n, m) array.
IO.puts("Testing triu_indices...")

try do
  result = SnakeBridge.Numpy.triu_indices(%{n: 10})
  IO.puts("  ✓ triu_indices: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ triu_indices: #{Exception.message(e)}")
end

# format_float_scientific [○ stateless]
# Format a floating-point scalar as a decimal string in scientific notat
IO.puts("Testing format_float_scientific...")

try do
  result = SnakeBridge.Numpy.format_float_scientific(%{x: 10})
  IO.puts("  ✓ format_float_scientific: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ format_float_scientific: #{Exception.message(e)}")
end

# geterrcall [○ stateless]
# Return the current callback function used on floating-point errors.
IO.puts("Testing geterrcall...")

try do
  result = SnakeBridge.Numpy.geterrcall()
  IO.puts("  ✓ geterrcall: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ geterrcall: #{Exception.message(e)}")
end

# iterable [○ stateless]
# Check whether or not an object can be iterated over.
IO.puts("Testing iterable...")

try do
  result = SnakeBridge.Numpy.iterable(%{y: 10})
  IO.puts("  ✓ iterable: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ iterable: #{Exception.message(e)}")
end

# format_float_positional [○ stateless]
# Format a floating-point scalar as a decimal string in positional notat
IO.puts("Testing format_float_positional...")

try do
  result = SnakeBridge.Numpy.format_float_positional(%{x: 10})
  IO.puts("  ✓ format_float_positional: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ format_float_positional: #{Exception.message(e)}")
end

# indices [○ stateless]
# Return an array representing the indices of a grid.
IO.puts("Testing indices...")

try do
  result = SnakeBridge.Numpy.indices(%{dimensions: [2, 2]})
  IO.puts("  ✓ indices: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ indices: #{Exception.message(e)}")
end

# typename [○ stateless]
# Return a description for the given data type code.
IO.puts("Testing typename...")

try do
  result = SnakeBridge.Numpy.typename(%{char: "f"})
  IO.puts("  ✓ typename: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ typename: #{Exception.message(e)}")
end

# tri [○ stateless]
# An array with ones at and below the given diagonal and zeros elsewhere
IO.puts("Testing tri...")

try do
  result = SnakeBridge.Numpy.tri(%{N: 10})
  IO.puts("  ✓ tri: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ tri: #{Exception.message(e)}")
end

# diag_indices [○ stateless]
# Return the indices to access the main diagonal of an array.
IO.puts("Testing diag_indices...")

try do
  result = SnakeBridge.Numpy.diag_indices(%{n: 10})
  IO.puts("  ✓ diag_indices: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ diag_indices: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
