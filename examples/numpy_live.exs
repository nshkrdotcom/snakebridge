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

# Configure Snakepit for gRPC
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.GRPCPython)
Application.put_env(:snakepit, :pooling_enabled, true)

Application.put_env(:snakepit, :pools, [
  %{
    name: :default,
    worker_profile: :process,
    pool_size: 2,
    adapter_module: Snakepit.Adapters.GRPCPython,
    adapter_args: ["--adapter", "snakebridge_adapter.adapter.SnakeBridgeAdapter"]
  }
])

Application.put_env(:snakepit, :log_level, :warning)

# Set PYTHONPATH
pythonpath = Path.join([File.cwd!(), "priv", "python"])
snakepit_python = Path.expand("deps/snakepit/priv/python")
System.put_env("PYTHONPATH", "#{pythonpath}:#{snakepit_python}")

# Use Snakepit venv
snakepit_venv = Path.expand("~/p/g/n/snakepit/.venv/bin/python3")
if File.exists?(snakepit_venv), do: System.put_env("SNAKEPIT_PYTHON", snakepit_venv)

# Install
Mix.install([
  {:snakepit, "~> 0.6"},
  {:snakebridge, path: "."},
  {:grpc, "~> 0.10.2"},
  {:protobuf, "~> 0.14.1"}
])

Application.put_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitAdapter)

IO.puts("\n🔢 SnakeBridge + NumPy: Complex Math from Elixir\n")
IO.puts(String.duplicate("=", 60))

# Check NumPy available
case System.cmd("python3", ["-c", "import numpy"],
       env: [{"PYTHONPATH", "#{pythonpath}:#{snakepit_python}"}],
       stderr_to_stdout: true
     ) do
  {_, 0} ->
    IO.puts("✓ NumPy detected\n")

  _ ->
    IO.puts("⚠️  NumPy not found. Installing...")
    {output, status} = System.cmd(snakepit_venv, ["-m", "pip", "install", "numpy"])

    if status == 0 do
      IO.puts("✓ NumPy installed\n")
    else
      IO.puts("✗ Failed to install NumPy")
      IO.puts(output)
      System.halt(1)
    end
end

Snakepit.run_as_script(fn ->
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
