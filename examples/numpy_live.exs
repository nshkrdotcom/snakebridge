#!/usr/bin/env elixir
#
# SnakeBridge NumPy Example - Real Python with Complex Math
#
# Run with: elixir examples/numpy_live.exs
#
# NumPy: Foundational library for numerical computing
# - Complex linear algebra (hard to do in pure Elixir)
# - Stateless mathematical functions (perfect for SnakeBridge)
# - No leaky abstractions

# Shared helper handles Mix.install + environment setup
Code.require_file("example_helpers.exs", __DIR__)

SnakeBridgeExample.setup(
  description: "SnakeBridge NumPy Example - Real Python with Complex Math",
  python_packages: ["numpy"]
)

IO.puts("\n🔢 SnakeBridge + NumPy: Complex Math from Elixir\n")
IO.puts(String.duplicate("=", 60))
IO.puts("✓ NumPy detected and ready\n")

SnakeBridgeExample.run(fn ->
  IO.puts("📡 Discovering NumPy library...")

  case SnakeBridge.discover("numpy") do
    {:ok, schema} ->
      IO.puts("✓ NumPy introspected!")
      IO.puts("  Version: #{schema["library_version"]}")

      function_names = Map.keys(schema["functions"]) |> Enum.take(10)
      IO.puts("  Sample functions: #{inspect(function_names)}")

      class_names = Map.keys(schema["classes"]) |> Enum.take(5)
      IO.puts("  Sample classes: #{inspect(class_names)}")

      IO.puts("\n📊 NumPy has:")
      IO.puts("  • #{map_size(schema["functions"])} functions")
      IO.puts("  • #{map_size(schema["classes"])} classes")

      IO.puts("\n💡 What NumPy brings to Elixir:")
      IO.puts("  • Linear algebra (matrix operations)")
      IO.puts("  • Statistical functions (mean, std, correlation)")
      IO.puts("  • Fourier transforms (FFT)")
      IO.puts("  • Random number generation")
      IO.puts("  • Array operations (reshape, slice, aggregate)")

      IO.puts("\n✅ Success! Can now use NumPy's scientific computing from Elixir")
      IO.puts("\n📝 Next: Generator needs to support module-level functions")
      IO.puts("   Then we could do: Numpy.array([1,2,3]), Numpy.mean(data), etc.")

    {:error, reason} ->
      IO.puts("✗ Discovery failed: #{inspect(reason)}")
  end

  IO.puts("\n" <> String.duplicate("=", 60) <> "\n")
end)
