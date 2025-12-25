defmodule Demo do
  @moduledoc """
  Run with: mix run -e Demo.run
  """

  def run do
    IO.puts("""
    ╔═══════════════════════════════════════════════════════════╗
    ║              SnakeBridge Demo                             ║
    ╚═══════════════════════════════════════════════════════════╝
    """)

    demo_generated_structure()
    demo_discovery()

    IO.puts("\nDone! Try `iex -S mix` to explore more.")
  end

  defp demo_generated_structure do
    IO.puts("── Generated Code ──────────────────────────────────────────")

    root = Path.expand("../lib/snakebridge_generated", __DIR__)
    IO.puts("  Root: #{root}")

    case File.ls(root) do
      {:ok, entries} ->
        adapters =
          entries
          |> Enum.reject(&(&1 == ".gitignore"))
          |> Enum.sort()

        if adapters == [] do
          IO.puts("  No adapters found. Run `mix compile`.")
        else
          IO.puts("  Adapters: #{Enum.join(adapters, ", ")}")

          Enum.each(adapters, fn adapter ->
            module_root = Path.join([root, adapter, adapter])
            meta_path = Path.join(module_root, "_meta.ex")
            module_path = Path.join(module_root, "#{adapter}.ex")
            classes_path = Path.join(module_root, "classes")

            case File.ls(module_root) do
              {:ok, files} ->
                items =
                  files
                  |> Enum.sort()
                  |> Enum.map(fn item ->
                    path = Path.join(module_root, item)
                    if File.dir?(path), do: item <> "/", else: item
                  end)

                IO.puts("    #{adapter}/#{adapter}/: #{Enum.join(items, ", ")}")
                IO.puts("      path: #{module_root}")
                IO.puts("      docs: #{meta_path}")
                IO.puts("      module: #{module_path}")
                if File.dir?(classes_path), do: IO.puts("      classes: #{classes_path}")

              {:error, _} ->
                IO.puts("    #{adapter}/#{adapter}/: (missing)")
            end
          end)
        end

      {:error, _} ->
        IO.puts("  Not found. Run `mix compile` to generate adapters.")
    end

    IO.puts("  Tip: docs are exposed via __functions__/__classes__/__search__ in each module.")
    IO.puts("")
  end

  defp demo_discovery do
    IO.puts("── Discovery & Docs ─────────────────────────────────────────")

    demo_module_discovery(Math, "Math", "sqrt")
    demo_module_discovery(Json, "Json", "dumps")
    demo_module_discovery(Sympy, "Sympy", "solve")

    IO.puts("")
  end

  defp demo_module_discovery(mod, label, search_term) do
    if Code.ensure_loaded?(mod) do
      IO.puts("  #{label}.__functions__() |> length() = #{length(mod.__functions__())}")

      IO.puts("\n  #{label}.__search__(#{inspect(search_term)}):")

      mod.__search__(search_term)
      |> Enum.take(3)
      |> Enum.each(fn {name, arity, _mod, doc} ->
        short_doc =
          (doc || "")
          |> String.split("\n")
          |> List.first()
          |> String.slice(0, 60)

        IO.puts("    - #{name}/#{arity}: #{short_doc}...")
      end)

      classes =
        if function_exported?(mod, :__classes__, 0) do
          mod.__classes__()
        else
          []
        end

      if classes != [] do
        IO.puts("\n  #{label}.__classes__():")

        classes
        |> Enum.take(3)
        |> Enum.each(fn entry ->
          {name, mod_ref, doc} = normalize_class_entry(entry)

          short_doc =
            (doc || "")
            |> String.split("\n")
            |> List.first()
            |> String.slice(0, 60)

          label =
            if mod_ref do
              "#{inspect(name)} (#{inspect(mod_ref)})"
            else
              inspect(name)
            end

          IO.puts("    - #{label}: #{short_doc}...")
        end)
      end
    else
      IO.puts("  #{label} module not available. Run `mix compile`.")
    end

    IO.puts("")
  end

  defp normalize_class_entry(entry) do
    case entry do
      {name, mod, doc} -> {name, mod, doc}
      {name, doc} -> {name, nil, doc}
      other -> {other, nil, nil}
    end
  end
end
