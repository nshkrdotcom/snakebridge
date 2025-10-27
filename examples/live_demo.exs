#!/usr/bin/env elixir
#
# SnakeBridge LIVE Demo
#
# Run with: elixir examples/live_demo.exs
#

# Shared helper handles Mix.install + environment setup
Code.require_file("example_helpers.exs", __DIR__)

SnakeBridgeExample.setup(description: "SnakeBridge LIVE Demo")

pythonpath = System.get_env("PYTHONPATH", "")
python_exec = System.get_env("SNAKEPIT_PYTHON", "python3")

# Check if Python adapter is available
python_ready =
  case System.cmd(
         python_exec,
         ["-c", "from snakebridge_adapter import SnakeBridgeAdapter"],
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

# At this point helper already announced the intro, focus on runtime output
IO.puts(String.duplicate("=", 60))
IO.puts("\n✓ Python adapter detected - using REAL Python via Snakepit\n")

SnakeBridgeExample.run(fn ->
  IO.puts("📡 Discovering Python's built-in json module...")

  case SnakeBridge.discover("json") do
    {:ok, schema} ->
      IO.puts("✓ Discovery successful!")
      IO.puts("  Version: #{schema["library_version"]}")
      IO.puts("  Functions: #{Map.keys(schema["functions"]) |> Enum.take(5) |> inspect()}")
      IO.puts("  Classes: #{Map.keys(schema["classes"]) |> inspect()}")

      IO.puts("\n📝 Schema has #{map_size(schema["functions"])} functions")

      # For now, just show we got the schema - generator needs work to handle functions
      IO.puts("\n✓ Live Python introspection working!")

      IO.puts(
        "\n⚠️  Next step: Update generator to create modules for functions (not just classes)"
      )

      IO.puts("   Current: Only generates from config.classes")
      IO.puts("   Needed: Also generate from config.functions")

      IO.puts("\n✅ Success! SnakeBridge discovered REAL Python library via Snakepit!\n")

    {:error, reason} ->
      IO.puts("✗ Discovery failed: #{inspect(reason)}")
  end

  IO.puts(String.duplicate("=", 60) <> "\n")
end)
