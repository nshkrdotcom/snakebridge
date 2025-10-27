#!/usr/bin/env elixir
#
# SnakeBridge LIVE Demo
#
# Run with: elixir examples/live_demo.exs
#

# Configure Snakepit for gRPC with SnakeBridge adapter
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.GRPCPython)
Application.put_env(:snakepit, :pooling_enabled, true)

Application.put_env(:snakepit, :pools, [
  %{
    name: :default,
    worker_profile: :process,
    pool_size: 2,
    adapter_module: Snakepit.Adapters.GRPCPython,
    adapter_config: %{
      python_module: "snakebridge_adapter.adapter",
      python_class: "SnakeBridgeAdapter"
    }
  }
])

Application.put_env(:snakepit, :pool_config, %{pool_size: 2})
Application.put_env(:snakepit, :grpc_port, 50051)
Application.put_env(:snakepit, :log_level, :warning)

# Set PYTHONPATH for both SnakeBridge and Snakepit
snakebridge_python = Path.join([File.cwd!(), "priv", "python"])
snakepit_python = Path.expand("deps/snakepit/priv/python")
pythonpath = "#{snakebridge_python}:#{snakepit_python}"
System.put_env("PYTHONPATH", pythonpath)

# Use Snakepit's venv Python (has grpcio, protobuf installed)
snakepit_venv_python = Path.expand("~/p/g/n/snakepit/.venv/bin/python3")

if File.exists?(snakepit_venv_python) do
  System.put_env("SNAKEPIT_PYTHON", snakepit_venv_python)
end

# Install dependencies
Mix.install([
  {:snakepit, "~> 0.6"},
  {:snakebridge, path: "."},
  {:grpc, "~> 0.10.2"},
  {:protobuf, "~> 0.14.1"}
])

# Check if Python adapter is available
python_ready =
  case System.cmd("python3", ["-c", "from snakebridge_adapter import SnakeBridgeAdapter"],
         env: [{"PYTHONPATH", pythonpath}],
         stderr_to_stdout: true
       ) do
    {_, 0} -> true
    _ -> false
  end

if not python_ready do
  IO.puts("\n⚠️  Python adapter not installed!\n")
  IO.puts("Run this command to set it up:")
  IO.puts("  $ ./scripts/setup_python.sh")
  IO.puts("")
  System.halt(1)
end

# Use LIVE mode (real Python via Snakepit)
Application.put_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitAdapter)

IO.puts("\n🐍 SnakeBridge LIVE Demo\n")
IO.puts(String.duplicate("=", 60))
IO.puts("\n✓ Python adapter detected - using REAL Python via Snakepit\n")

# Run with Snakepit script wrapper (handles pool startup/cleanup)
Snakepit.run_as_script(fn ->
  IO.puts("📡 Discovering Python library (dspy)...")

  case SnakeBridge.discover("dspy") do
    {:ok, schema} ->
      IO.puts("✓ Discovery successful!")
      IO.puts("  Version: #{schema["library_version"]}")
      IO.puts("  Classes: #{Map.keys(schema["classes"]) |> inspect()}")

      IO.puts("\n⚙️  Generating Elixir modules...")
      {:ok, modules} = SnakeBridge.integrate("dspy")

      IO.puts("✓ Generated #{length(modules)} module(s)")
      Enum.each(modules, fn m -> IO.puts("  • #{inspect(m)}") end)

      [predict | _] = modules

      IO.puts("\n🚀 Creating Python instance...")
      {:ok, instance} = predict.create(%{signature: "question -> answer"})
      {session, instance_id} = instance

      IO.puts("✓ Instance created!")
      IO.puts("  Session: #{session}")
      IO.puts("  Instance ID: #{instance_id}")

      IO.puts("\n📞 Calling method on instance...")
      {:ok, result} = predict.__call__(instance, %{question: "What is SnakeBridge?"})

      IO.puts("✓ Method executed!")
      IO.puts("  Result: #{inspect(result, limit: 3)}")

      IO.puts("\n✅ Success! SnakeBridge called REAL Python via Snakepit!\n")

    {:error, reason} ->
      IO.puts("✗ Discovery failed: #{inspect(reason)}")
  end

  IO.puts(String.duplicate("=", 60) <> "\n")
end)
