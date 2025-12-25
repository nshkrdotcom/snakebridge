#!/usr/bin/env elixir

# SnakeBridge Generator Demo
#
# This script demonstrates the complete workflow of the SnakeBridge v2 Generator:
# 1. Introspect a Python module
# 2. Generate Elixir source code with typespecs and documentation
# 3. Write the generated code to a file
#
# Usage:
#   elixir examples/generator_demo.exs [module_name]
#
# Example:
#   elixir examples/generator_demo.exs math
#   elixir examples/generator_demo.exs json

Mix.install([
  {:snakebridge, path: Path.expand("..", __DIR__)},
  {:jason, "~> 1.4"}
])

alias SnakeBridge.Generator.{Introspector, SourceWriter}

defmodule GeneratorDemo do
  def run(module_name \\ "math") do
    IO.puts("=== SnakeBridge Generator Demo ===\n")
    IO.puts("Introspecting Python module: #{module_name}\n")

    case Introspector.introspect(module_name) do
      {:ok, introspection} ->
        display_introspection_summary(introspection)
        generate_and_display_code(introspection, module_name)

      {:error, reason} ->
        IO.puts("Error: #{reason}")
        exit({:shutdown, 1})
    end
  end

  defp display_introspection_summary(introspection) do
    IO.puts("Module: #{introspection["module"]}")

    if version = introspection["module_version"] do
      IO.puts("Version: #{version}")
    end

    num_functions = length(introspection["functions"] || [])
    num_classes = length(introspection["classes"] || [])

    IO.puts("Functions: #{num_functions}")
    IO.puts("Classes: #{num_classes}")

    # Show a few function names
    if num_functions > 0 do
      IO.puts("\nSample functions:")

      introspection["functions"]
      |> Enum.take(5)
      |> Enum.each(fn func ->
        params = func["parameters"] || []
        param_names = Enum.map(params, & &1["name"]) |> Enum.join(", ")
        IO.puts("  - #{func["name"]}(#{param_names})")
      end)
    end

    IO.puts("\n" <> String.duplicate("=", 60) <> "\n")
  end

  defp generate_and_display_code(introspection, module_name) do
    # Generate with custom options
    elixir_module_name =
      module_name
      |> String.split(".")
      |> Enum.map(&Macro.camelize/1)
      |> Enum.join(".")

    IO.puts("Generating Elixir module: #{elixir_module_name}\n")

    source =
      SourceWriter.generate(introspection,
        module_name: elixir_module_name,
        use_snakebridge: true,
        add_python_annotations: true
      )

    IO.puts("Generated code preview (first 50 lines):\n")
    IO.puts(String.duplicate("-", 60))

    source
    |> String.split("\n")
    |> Enum.take(50)
    |> Enum.join("\n")
    |> IO.puts()

    IO.puts("\n" <> String.duplicate("-", 60))

    # Optionally write to file
    output_dir = Path.join([File.cwd!(), "examples", "generated"])
    File.mkdir_p!(output_dir)

    output_file = Path.join(output_dir, "#{module_name}_adapter.ex")

    case SourceWriter.generate_file(introspection, output_file,
           module_name: elixir_module_name,
           use_snakebridge: true,
           add_python_annotations: true
         ) do
      :ok ->
        IO.puts("\n✓ Generated code written to: #{output_file}")

      {:error, reason} ->
        IO.puts("\n✗ Failed to write file: #{inspect(reason)}")
    end
  end
end

# Run the demo
module_name = System.argv() |> List.first() || "math"
GeneratorDemo.run(module_name)
