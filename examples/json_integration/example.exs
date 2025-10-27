#!/usr/bin/env elixir
#
# SnakeBridge Example: JSON Integration
#
# Run with: mix run examples/json_integration/example.exs
#
# This example shows how to use SnakeBridge to integrate Python's json module
# and call it from Elixir.

IO.puts("\n🐍 SnakeBridge Example: Python JSON Integration\n")
IO.puts(String.duplicate("=", 60))

# Step 1: Discover the json module
IO.puts("\n📡 Step 1: Discovering Python's json module...")

case SnakeBridge.discover("json", depth: 1) do
  {:ok, schema} ->
    IO.puts("✓ Discovery successful!")
    IO.puts("  Library version: #{schema["library_version"]}")
    IO.puts("  Functions found: #{map_size(schema["functions"])}")
    IO.puts("  Classes found: #{map_size(schema["classes"])}")

    # Show discovered functions
    function_names = Map.keys(schema["functions"]) |> Enum.take(5)
    IO.puts("  Sample functions: #{inspect(function_names)}")

    # Step 2: Convert to config
    IO.puts("\n⚙️  Step 2: Converting schema to SnakeBridge config...")
    config = SnakeBridge.Discovery.schema_to_config(schema, python_module: "json")
    IO.puts("✓ Config created")
    IO.puts("  Python module: #{config.python_module}")
    IO.puts("  Functions: #{length(config.functions)}")

    # Step 3: Generate Elixir modules
    IO.puts("\n🏗️  Step 3: Generating Elixir wrapper modules...")

    case SnakeBridge.generate(config) do
      {:ok, modules} ->
        IO.puts("✓ Modules generated: #{inspect(modules)}")

        [json_module | _] = modules

        # Step 4: Use the generated module
        IO.puts("\n🚀 Step 4: Calling Python's json.dumps from Elixir...")

        test_data = %{
          message: "Hello from SnakeBridge!",
          timestamp: System.system_time(:second),
          features: ["type-safe", "zero-code", "fast"],
          nested: %{
            author: "nshkrdotcom",
            project: "SnakeBridge"
          }
        }

        IO.puts("  Input data: #{inspect(test_data, pretty: true)}")

        case json_module.dumps(test_data) do
          {:ok, json_string} ->
            IO.puts("\n✓ Encoding successful!")
            IO.puts("  JSON output: #{json_string}")

            # Step 5: Decode it back
            IO.puts("\n🔄 Step 5: Calling Python's json.loads...")

            case json_module.loads(%{s: json_string}) do
              {:ok, decoded} ->
                IO.puts("✓ Decoding successful!")
                IO.puts("  Decoded data: #{inspect(decoded, pretty: true)}")

                # Verify roundtrip
                IO.puts("\n✅ Step 6: Verifying roundtrip...")

                if decoded["message"] == test_data.message &&
                     decoded["timestamp"] == test_data.timestamp &&
                     decoded["nested"]["author"] == test_data.nested.author do
                  IO.puts("✓ Roundtrip verified! Data survived encode/decode cycle.")
                  IO.puts("\n🎉 Success! SnakeBridge is working!\n")
                else
                  IO.puts("✗ Roundtrip verification failed")
                  IO.puts("  Expected: #{inspect(test_data)}")
                  IO.puts("  Got: #{inspect(decoded)}")
                end

              {:error, reason} ->
                IO.puts("✗ Decoding failed: #{inspect(reason)}")
            end

          {:error, reason} ->
            IO.puts("✗ Encoding failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("✗ Module generation failed: #{inspect(reason)}")
    end

  {:error, reason} ->
    IO.puts("✗ Discovery failed: #{inspect(reason)}")
    IO.puts("\nThis is expected if running with mocks.")
    IO.puts("To run with real Python:")
    IO.puts("  1. Setup Python: cd priv/python && pip3 install -e .")
    IO.puts("  2. Configure Snakepit in config/runtime.exs")
    IO.puts("  3. Run: mix run examples/json_integration/example.exs")
end

IO.puts(String.duplicate("=", 60))
