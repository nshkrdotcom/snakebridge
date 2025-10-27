#!/usr/bin/env elixir
#
# SnakeBridge Simple Example (with Mocks)
#
# Run with: mix run examples/simple_mock_example.exs
#
# This example demonstrates SnakeBridge functionality using mocks.
# For real Python integration, see examples/json_integration/

IO.puts("\n🐍 SnakeBridge Mock Example\n")
IO.puts(String.duplicate("=", 60))

# Step 1: Discover a Python library (using mock)
IO.puts("\n📡 Step 1: Discovering Python library...")
IO.puts("  (Using SnakepitMock - returns simulated DSPy schema)")

{:ok, schema} = SnakeBridge.discover("dspy")

IO.puts("✓ Discovery successful!")
IO.puts("  Library: dspy")
IO.puts("  Version: #{schema["library_version"]}")
IO.puts("  Classes: #{schema["classes"] |> Map.keys() |> inspect()}")

# Step 2: Convert to configuration
IO.puts("\n⚙️  Step 2: Converting to SnakeBridge config...")

config = SnakeBridge.Discovery.schema_to_config(schema, python_module: "dspy")

IO.puts("✓ Config created")
IO.puts("  Module: #{config.python_module}")
IO.puts("  Classes: #{length(config.classes)}")
IO.puts("  Functions: #{length(config.functions)}")

# Step 3: Generate Elixir wrapper modules
IO.puts("\n🏗️  Step 3: Generating Elixir modules...")

{:ok, modules} = SnakeBridge.generate(config)

IO.puts("✓ Generated #{length(modules)} module(s):")
Enum.each(modules, fn mod -> IO.puts("  - #{inspect(mod)}") end)

# Step 4: Use generated modules (with mock)
IO.puts("\n🚀 Step 4: Using generated modules...")

[predict_module | _] = modules

IO.puts("  Creating instance of #{inspect(predict_module)}...")
{:ok, instance} = predict_module.create(%{signature: "question -> answer"})

{session_id, instance_id} = instance
IO.puts("✓ Instance created!")
IO.puts("  Session ID: #{session_id}")
IO.puts("  Instance ID: #{instance_id}")

# Step 5: Call method on instance
IO.puts("\n📞 Step 5: Calling method on instance...")
IO.puts("  Calling __call__ method...")

{:ok, result} = predict_module.__call__(instance, %{question: "What is SnakeBridge?"})

IO.puts("✓ Method call successful!")
IO.puts("  Result: #{inspect(result, pretty: true)}")

# Step 6: One-step integration
IO.puts("\n⚡ Step 6: Using one-step integrate() API...")

{:ok, modules2} = SnakeBridge.integrate("dspy")

IO.puts("✓ Integrated in one call!")
IO.puts("  Modules: #{inspect(modules2)}")

# Step 7: With full return
IO.puts("\n📦 Step 7: Getting full response...")

{:ok, %{config: config2, modules: modules3}} = SnakeBridge.integrate("dspy", return: :full)

IO.puts("✓ Full integration complete!")
IO.puts("  Config module: #{config2.python_module}")
IO.puts("  Config version: #{config2.version}")
IO.puts("  Modules generated: #{length(modules3)}")

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("\n✅ Example Complete!\n")
IO.puts("This example used SnakepitMock (fake Python responses).")
IO.puts("To use with REAL Python, see:")
IO.puts("  - docs/20251026/COMPLETE_USAGE_EXAMPLE.md")
IO.puts("  - examples/json_integration/example.exs (after Snakepit setup)")
IO.puts("\n" <> String.duplicate("=", 60) <> "\n")
