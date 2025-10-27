#!/usr/bin/env elixir
#
# SnakeBridge API Demo
#
# Run with: mix run examples/api_demo.exs
#
# This demonstrates the SnakeBridge API and shows what the generated
# code looks like without actually calling Python.

IO.puts("\n🐍 SnakeBridge API Demonstration\n")
IO.puts(String.duplicate("=", 60))

# Demo 1: Show config structure
IO.puts("\n📋 Demo 1: Configuration Structure")
IO.puts(String.duplicate("-", 60))

config = %SnakeBridge.Config{
  python_module: "json",
  version: "2.0.9",
  functions: [
    %{
      python_path: "json.dumps",
      elixir_name: :dumps,
      args: %{obj: {:required, :any}}
    },
    %{
      python_path: "json.loads",
      elixir_name: :loads,
      args: %{s: {:required, :string}}
    }
  ],
  classes: []
}

IO.puts("Created config for Python module: #{config.python_module}")
IO.puts("Functions: #{length(config.functions)}")
IO.puts("Classes: #{length(config.classes)}")

# Demo 2: Generate module and show the code
IO.puts("\n🏗️  Demo 2: Code Generation")
IO.puts(String.duplicate("-", 60))

# Use TestFixtures to show a real example
descriptor = %{
  name: "JsonModule",
  python_path: "json",
  docstring: "Python's built-in JSON encoder/decoder",
  methods: [
    %{
      name: "dumps",
      elixir_name: :dumps,
      streaming: false,
      docstring: "Serialize obj to JSON formatted string"
    }
  ]
}

ast = SnakeBridge.Generator.generate_module(descriptor, config)
code = Macro.to_string(ast)

IO.puts("Generated Elixir module code:")
IO.puts("")
IO.puts(String.slice(code, 0..800))
IO.puts("...")
IO.puts("")

# Demo 3: Type system
IO.puts("\n🔧 Demo 3: Type System")
IO.puts(String.duplicate("-", 60))

IO.puts("Python type mappings:")

IO.puts(
  "  Python int    → Elixir #{inspect(SnakeBridge.TypeSystem.Mapper.to_elixir_spec(%{kind: "primitive", primitive_type: "int"}))}"
)

IO.puts(
  "  Python str    → Elixir #{inspect(SnakeBridge.TypeSystem.Mapper.to_elixir_spec(%{kind: "primitive", primitive_type: "str"}))}"
)

IO.puts(
  "  Python list   → Elixir #{inspect(SnakeBridge.TypeSystem.Mapper.to_elixir_spec(%{kind: "list", element_type: %{kind: "primitive", primitive_type: "int"}}))}"
)

IO.puts(
  "  Python dict   → Elixir #{inspect(SnakeBridge.TypeSystem.Mapper.to_elixir_spec(%{kind: "dict", key_type: %{kind: "primitive", primitive_type: "str"}, value_type: %{kind: "primitive", primitive_type: "any"}}))}"
)

IO.puts("\nElixir value → Python type inference:")
IO.puts("  42          → #{inspect(SnakeBridge.TypeSystem.Mapper.infer_python_type(42))}")
IO.puts("  \"hello\"     → #{inspect(SnakeBridge.TypeSystem.Mapper.infer_python_type("hello"))}")
IO.puts("  [1, 2, 3]   → #{inspect(SnakeBridge.TypeSystem.Mapper.infer_python_type([1, 2, 3]))}")
IO.puts("  %{a: 1}     → #{inspect(SnakeBridge.TypeSystem.Mapper.infer_python_type(%{a: 1}))}")

# Demo 4: Python class path conversion
IO.puts("\n🔤 Demo 4: Name Transformations")
IO.puts(String.duplicate("-", 60))

examples = [
  {"dspy.Predict", "DSPy.Predict"},
  {"langchain.chains.LLMChain", "Langchain.Chains.LLMChain"},
  {"numpy.ndarray", "Numpy.Ndarray"}
]

IO.puts("Python → Elixir module names:")

Enum.each(examples, fn {python, expected} ->
  result = SnakeBridge.TypeSystem.Mapper.python_class_to_elixir_module(python)
  status = if result == String.to_atom(expected), do: "✓", else: "✗"
  IO.puts("  #{status} #{python} → #{inspect(result)}")
end)

# Demo 5: Configuration validation
IO.puts("\n✅ Demo 5: Configuration Validation")
IO.puts(String.duplicate("-", 60))

case SnakeBridge.Config.validate(config) do
  {:ok, valid_config} ->
    IO.puts("✓ Configuration is valid")
    IO.puts("  Module: #{valid_config.python_module}")
    IO.puts("  Compilation mode: #{valid_config.compilation_mode}")

  {:error, errors} ->
    IO.puts("✗ Configuration has errors:")
    Enum.each(errors, fn err -> IO.puts("  - #{err}") end)
end

# Demo 6: Cache system
IO.puts("\n💾 Demo 6: Cache System")
IO.puts(String.duplicate("-", 60))

hash = SnakeBridge.Config.hash(config)
IO.puts("Config hash: #{hash}")

{:ok, cache_path} = SnakeBridge.Cache.store(config)
IO.puts("✓ Config cached to: #{cache_path}")

{:ok, loaded_config} = SnakeBridge.Cache.load(cache_path)
IO.puts("✓ Config loaded from cache")
IO.puts("  Loaded module: #{loaded_config.python_module}")

# Verify hash matches
if SnakeBridge.Config.hash(loaded_config) == hash do
  IO.puts("✓ Cache integrity verified (hashes match)")
else
  IO.puts("✗ Cache corruption detected (hashes differ)")
end

# Demo 7: Show public API
IO.puts("\n📚 Demo 7: Public API Overview")
IO.puts(String.duplicate("-", 60))

IO.puts("""
SnakeBridge provides three main functions:

1. SnakeBridge.discover(module_path, opts)
   - Introspects Python library
   - Returns schema with classes/functions
   - Example: {:ok, schema} = SnakeBridge.discover("json")

2. SnakeBridge.generate(config)
   - Generates Elixir modules from config
   - Returns list of module atoms
   - Example: {:ok, [JsonMod]} = SnakeBridge.generate(config)

3. SnakeBridge.integrate(module_path, opts)
   - One-step: discover + generate
   - Convenience function
   - Example: {:ok, modules} = SnakeBridge.integrate("json")
""")

IO.puts(String.duplicate("=", 60))
IO.puts("\n✅ Demo Complete!\n")
IO.puts("📝 What you just saw:")
IO.puts("   • Configuration and validation")
IO.puts("   • Code generation (Python → Elixir)")
IO.puts("   • Type system mappings")
IO.puts("   • Caching")
IO.puts("")
IO.puts("🤔 This used internal APIs only (no Python executed)")
IO.puts("")
IO.puts("🚀 Want to call REAL Python?")
IO.puts("")
IO.puts("   Just run: ./scripts/setup_python.sh")
IO.puts("   Then:     mix test --include real_python")
IO.puts("")
IO.puts(String.duplicate("=", 60) <> "\n")
