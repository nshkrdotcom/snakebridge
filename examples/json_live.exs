#!/usr/bin/env elixir
#
# JSON Example - Built-in Python library
# Run: elixir examples/json_live.exs

Code.require_file("example_helpers.exs", __DIR__)

SnakeBridgeExample.setup(
  # json is built-in
  python_packages: [],
  description: "JSON Encoding/Decoding from Elixir"
)

SnakeBridgeExample.run(fn ->
  IO.puts("📡 Discovering Python's json module...")

  {:ok, schema} = SnakeBridge.discover("json")

  IO.puts("✓ Discovered json module")
  IO.puts("  Version: #{schema["library_version"]}")
  IO.puts("  Functions: #{Map.keys(schema["functions"]) |> Enum.take(5) |> inspect()}")

  IO.puts("\n🔧 Generating Elixir modules for json...")

  # Convert to config and generate modules (classes + functions)
  config = SnakeBridge.Discovery.schema_to_config(schema, python_module: "json")
  {:ok, modules} = SnakeBridge.generate(config)

  IO.puts("✓ Generated #{length(modules)} modules: #{inspect(modules)}")

  # Find the module with the dumps/loads functions
  json_module =
    Enum.find(modules, fn mod ->
      function_exported?(mod, :dumps, 0) || function_exported?(mod, :dumps, 1) ||
        function_exported?(mod, :dumps, 2)
    end)

  IO.puts("✓ Using function module: #{inspect(json_module)}")

  IO.puts("\n🚀 Calling json.dumps()...")
  test_data = %{message: "Hello from Elixir", value: 42, nested: %{key: "value"}}
  IO.puts("  Input: #{inspect(test_data)}")

  {:ok, json_string} = json_module.dumps(%{obj: test_data})
  IO.puts("  Output: #{json_string}")

  IO.puts("\n🚀 Calling json.loads()...")
  IO.puts("  Input: #{inspect(json_string)}")

  {:ok, decoded} = json_module.loads(%{s: json_string})
  IO.puts("  Output: #{inspect(decoded)}")

  IO.puts("\n✅ Roundtrip successful!")
  IO.puts("  Original: #{inspect(test_data)}")
  IO.puts("  Decoded:  #{inspect(decoded)}")

  IO.puts("\n✅ Success! Function generation and execution working!\n")
end)
