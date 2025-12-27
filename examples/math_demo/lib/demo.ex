defmodule Demo do
  @moduledoc """
  Run with: mix run -e Demo.run
  """

  def run do
    Snakepit.run_as_script(fn ->
      IO.puts("""
      ╔═══════════════════════════════════════════════════════════╗
      ║              SnakeBridge v3 Demo                          ║
      ╚═══════════════════════════════════════════════════════════╝
      """)

      demo_generated_structure()
      MathDemo.discover()
      demo_runtime_math()

      IO.puts("\nDone! Try `iex -S mix` to explore more.")
    end)
    |> case do
      {:error, reason} ->
        IO.puts("Snakepit script failed: #{inspect(reason)}")

      _ ->
        :ok
    end
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

  defp demo_runtime_math do
    IO.puts("=== Runtime Math ===")

    case MathDemo.compute_sample() do
      {:ok, %{sqrt: sqrt, sin: sin, cos: cos}} ->
        IO.puts("  sqrt(2) = #{sqrt}")
        IO.puts("  sin(1.0) = #{sin}")
        IO.puts("  cos(0.0) = #{cos}")

      {:error, reason} ->
        IO.puts("  Runtime call failed: #{inspect(reason)}")
        IO.puts("  Ensure Snakepit is configured and Python is available.")
    end

    IO.puts("")
  end
end
