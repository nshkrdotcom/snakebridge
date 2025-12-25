# stateful_examples.exs
# Auto-generated examples for SnakeBridge.Numpy
# Run with: mix run examples/generated/numpy/stateful_examples.exs

Application.ensure_all_started(:snakebridge)
# Give snakepit time to start
Process.sleep(1000)

IO.puts("=" |> String.duplicate(60))
IO.puts("  SnakeBridge.Numpy Examples")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# load [● stateful]
# Load arrays or pickled objects from ``.npy``, ``.npz`` or pickled file
IO.puts("Testing load...")

try do
  result = SnakeBridge.Numpy.load(%{file: "/tmp/test"})
  IO.puts("  ✓ load: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ load: #{Exception.message(e)}")
end

# isfortran [● stateful]
# Check if the array is Fortran contiguous but *not* C contiguous.
IO.puts("Testing isfortran...")

try do
  result = SnakeBridge.Numpy.isfortran(%{a: "test"})
  IO.puts("  ✓ isfortran: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ isfortran: #{Exception.message(e)}")
end

# kaiser [● stateful]
# Return the Kaiser window.
IO.puts("Testing kaiser...")

try do
  result = SnakeBridge.Numpy.kaiser(%{M: 10, beta: "test"})
  IO.puts("  ✓ kaiser: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ kaiser: #{Exception.message(e)}")
end

# row_stack [● stateful]
# Stack arrays in sequence vertically (row wise).
IO.puts("Testing row_stack...")

try do
  result = SnakeBridge.Numpy.row_stack(%{tup: "test"})
  IO.puts("  ✓ row_stack: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ row_stack: #{Exception.message(e)}")
end

# show_runtime [● stateful]
# Print information about various resources in the system
IO.puts("Testing show_runtime...")

try do
  result = SnakeBridge.Numpy.show_runtime()
  IO.puts("  ✓ show_runtime: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ show_runtime: #{Exception.message(e)}")
end

# full [● stateful]
# Return a new array of given shape and type, filled with `fill_value`.
IO.puts("Testing full...")

try do
  result = SnakeBridge.Numpy.full(%{shape: [2, 2], fill_value: "test"})
  IO.puts("  ✓ full: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ full: #{Exception.message(e)}")
end

# ones [● stateful]
# Return a new array of given shape and type, filled with ones.
IO.puts("Testing ones...")

try do
  result = SnakeBridge.Numpy.ones(%{shape: [2, 2]})
  IO.puts("  ✓ ones: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ ones: #{Exception.message(e)}")
end

# loadtxt [● stateful]
# Load data from a text file.
IO.puts("Testing loadtxt...")

try do
  result = SnakeBridge.Numpy.loadtxt(%{fname: "test"})
  IO.puts("  ✓ loadtxt: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ loadtxt: #{Exception.message(e)}")
end

# require [● stateful]
# Return an ndarray of the provided type that satisfies requirements.
IO.puts("Testing require...")

try do
  result = SnakeBridge.Numpy.require(%{a: "test"})
  IO.puts("  ✓ require: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ require: #{Exception.message(e)}")
end

# show_config [● stateful]
# Show libraries and system information on which NumPy was built
IO.puts("Testing show_config...")

try do
  result = SnakeBridge.Numpy.show_config()
  IO.puts("  ✓ show_config: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ show_config: #{Exception.message(e)}")
end

# isscalar [● stateful]
# Returns True if the type of `element` is a scalar type.
IO.puts("Testing isscalar...")

try do
  result = SnakeBridge.Numpy.isscalar(%{element: "test"})
  IO.puts("  ✓ isscalar: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ isscalar: #{Exception.message(e)}")
end

# asmatrix [● stateful]
# Interpret the input as a matrix.
IO.puts("Testing asmatrix...")

try do
  result = SnakeBridge.Numpy.asmatrix(%{data: [1, 2, 3]})
  IO.puts("  ✓ asmatrix: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ asmatrix: #{Exception.message(e)}")
end

# seterrcall [● stateful]
# Set the floating-point error callback function or log object.
IO.puts("Testing seterrcall...")

try do
  result = SnakeBridge.Numpy.seterrcall(%{func: "test"})
  IO.puts("  ✓ seterrcall: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ seterrcall: #{Exception.message(e)}")
end

# info [● stateful]
# Get help information for an array, function, class, or module.
IO.puts("Testing info...")

try do
  result = SnakeBridge.Numpy.info()
  IO.puts("  ✓ info: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ info: #{Exception.message(e)}")
end

# hanning [● stateful]
# Return the Hanning window.
IO.puts("Testing hanning...")

try do
  result = SnakeBridge.Numpy.hanning(%{M: 10})
  IO.puts("  ✓ hanning: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ hanning: #{Exception.message(e)}")
end

# binary_repr [● stateful]
# Return the binary representation of the input number as a string.
IO.puts("Testing binary_repr...")

try do
  result = SnakeBridge.Numpy.binary_repr(%{num: 10})
  IO.puts("  ✓ binary_repr: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ binary_repr: #{Exception.message(e)}")
end

# asarray_chkfinite [● stateful]
# Convert the input to an array, checking for NaNs or Infs.
IO.puts("Testing asarray_chkfinite...")

try do
  result = SnakeBridge.Numpy.asarray_chkfinite(%{a: "test"})
  IO.puts("  ✓ asarray_chkfinite: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ asarray_chkfinite: #{Exception.message(e)}")
end

# bmat [● stateful]
# Build a matrix object from a string, nested sequence, or array.
IO.puts("Testing bmat...")

try do
  result = SnakeBridge.Numpy.bmat(%{obj: %{}})
  IO.puts("  ✓ bmat: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ bmat: #{Exception.message(e)}")
end

# fromregex [● stateful]
# Construct an array from a text file, using regular expression parsing.
IO.puts("Testing fromregex...")

try do
  result = SnakeBridge.Numpy.fromregex(%{file: "/tmp/test", regexp: ".*", dtype: "int64"})
  IO.puts("  ✓ fromregex: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ fromregex: #{Exception.message(e)}")
end

# seterr [● stateful]
# Set how floating-point errors are handled.
IO.puts("Testing seterr...")

try do
  result = SnakeBridge.Numpy.seterr()
  IO.puts("  ✓ seterr: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ seterr: #{Exception.message(e)}")
end

# set_printoptions [● stateful]
# Set printing options.
IO.puts("Testing set_printoptions...")

try do
  result = SnakeBridge.Numpy.set_printoptions()
  IO.puts("  ✓ set_printoptions: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ set_printoptions: #{Exception.message(e)}")
end

# printoptions [● stateful]
# Context manager for setting print options.
IO.puts("Testing printoptions...")

try do
  result = SnakeBridge.Numpy.printoptions()
  IO.puts("  ✓ printoptions: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ printoptions: #{Exception.message(e)}")
end

# hamming [● stateful]
# Return the Hamming window.
IO.puts("Testing hamming...")

try do
  result = SnakeBridge.Numpy.hamming(%{M: 10})
  IO.puts("  ✓ hamming: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ hamming: #{Exception.message(e)}")
end

# genfromtxt [● stateful]
# Load data from a text file, with missing values handled as specified.
IO.puts("Testing genfromtxt...")

try do
  result = SnakeBridge.Numpy.genfromtxt(%{fname: "test"})
  IO.puts("  ✓ genfromtxt: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ genfromtxt: #{Exception.message(e)}")
end

# eye [● stateful]
# Return a 2-D array with ones on the diagonal and zeros elsewhere.
IO.puts("Testing eye...")

try do
  result = SnakeBridge.Numpy.eye(%{N: 10})
  IO.puts("  ✓ eye: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ eye: #{Exception.message(e)}")
end

# bartlett [● stateful]
# Return the Bartlett window.
IO.puts("Testing bartlett...")

try do
  result = SnakeBridge.Numpy.bartlett(%{M: 10})
  IO.puts("  ✓ bartlett: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ bartlett: #{Exception.message(e)}")
end

# blackman [● stateful]
# Return the Blackman window.
IO.puts("Testing blackman...")

try do
  result = SnakeBridge.Numpy.blackman(%{M: 10})
  IO.puts("  ✓ blackman: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ blackman: #{Exception.message(e)}")
end

# get_include [● stateful]
# Return the directory that contains the NumPy \*.h header files.
IO.puts("Testing get_include...")

try do
  result = SnakeBridge.Numpy.get_include()
  IO.puts("  ✓ get_include: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ get_include: #{Exception.message(e)}")
end

# fromfunction [● stateful]
# Construct an array by executing a function over each coordinate.
IO.puts("Testing fromfunction...")

try do
  result = SnakeBridge.Numpy.fromfunction(%{function: "test", shape: [2, 2]})
  IO.puts("  ✓ fromfunction: #{inspect(result, limit: 3, printable_limit: 50)}")
rescue
  e -> IO.puts("  ✗ fromfunction: #{Exception.message(e)}")
end

IO.puts("")
IO.puts("Done!")
