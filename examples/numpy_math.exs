#!/usr/bin/env elixir
#
# NumPy Example - Scientific computing from Elixir
# Run: elixir examples/numpy_math.exs

Code.require_file("example_helpers.exs", __DIR__)

SnakeBridgeExample.setup(
  # Auto-installs if missing
  python_packages: ["numpy"],
  description: "NumPy Scientific Computing"
)

SnakeBridgeExample.run(fn ->
  IO.puts("📡 Discovering NumPy...")

  {:ok, schema} = SnakeBridge.discover("numpy")

  IO.puts("✓ NumPy introspected!")
  IO.puts("  Version: #{schema["library_version"]}")
  IO.puts("  Functions: #{map_size(schema["functions"])}")
  IO.puts("  Classes: #{map_size(schema["classes"])}")

  IO.puts("\n💡 What NumPy provides:")
  IO.puts("  • Linear algebra: dot products, matrix operations")
  IO.puts("  • Statistics: mean, median, std, correlations")
  IO.puts("  • FFT: Fourier transforms")
  IO.puts("  • Random: Scientific random number generation")
  IO.puts("  • Arrays: N-dimensional array operations")

  IO.puts("\n✅ NumPy discovered! Ready for scientific computing from Elixir\n")
end)
