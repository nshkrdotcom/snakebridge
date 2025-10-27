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
  IO.puts("  Functions: #{Map.keys(schema["functions"]) |> inspect()}")

  IO.puts("\n✅ Success! Live Python introspection working!\n")
end)
