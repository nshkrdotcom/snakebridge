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

  IO.puts("\n💡 Sample functions discovered:")

  sample_functions =
    schema["functions"]
    |> Map.keys()
    |> Enum.filter(&String.contains?(&1, "mean"))
    |> Enum.take(3)

  IO.puts("  #{inspect(sample_functions)}")

  IO.puts("\n💡 What NumPy provides:")
  IO.puts("  • Linear algebra: dot products, matrix operations")
  IO.puts("  • Statistics: mean, median, std, correlations")
  IO.puts("  • FFT: Fourier transforms")
  IO.puts("  • Random: Scientific random number generation")
  IO.puts("  • Arrays: N-dimensional array operations")

  IO.puts("\n🔧 Generating Elixir modules for NumPy...")
  config = SnakeBridge.Discovery.schema_to_config(schema, python_module: "numpy")

  IO.puts("  ✓ Config created with #{length(config.functions)} functions")
  IO.puts("  ✓ Config created with #{length(config.classes)} classes")

  # Note: We don't generate all modules here as NumPy has 600+ functions
  # But the framework is ready to generate them on demand
  IO.puts("\n✅ NumPy discovered! Function generation ready!")

  IO.puts(
    "✅ SnakeBridge can now generate type-safe wrappers for #{map_size(schema["functions"])} NumPy functions!\n"
  )
end)
