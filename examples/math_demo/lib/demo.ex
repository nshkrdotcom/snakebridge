defmodule Demo do
  @moduledoc """
  Run with: mix run -e Demo.run
  """

  def run do
    IO.puts("""
    ╔═══════════════════════════════════════════════════════════╗
    ║              SnakeBridge v3 Demo                          ║
    ╚═══════════════════════════════════════════════════════════╝
    """)

    demo_generated_structure()
    MathDemo.discover()

    IO.puts("\nDone! Try `iex -S mix` to explore more.")
  end

  defp demo_generated_structure do
    IO.puts("── Generated Code ──────────────────────────────────────────")

    case MathDemo.generated_structure() do
      {:ok, info} ->
        IO.puts("  Root: #{info.root}")
        IO.puts("  Libraries: #{Enum.join(info.libraries, ", ")}")
        IO.puts("  Files: #{Enum.join(info.files, ", ")}")

      {:error, _} ->
        IO.puts("  Not found. Run `mix compile` to generate bindings.")
    end

    IO.puts("")
  end
end
