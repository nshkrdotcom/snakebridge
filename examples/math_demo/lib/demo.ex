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
      demo_runtime_math_verbose()

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

  defp demo_runtime_math_verbose do
    IO.puts("=== Runtime Math (Verbose) ===")
    IO.puts("")

    if Code.ensure_loaded?(Math) do
      # Call 1: sqrt(2)
      call("Math.sqrt/1",
        module: "math",
        function: "sqrt",
        args: [2]
      )

      sqrt_result = Math.sqrt(2)
      print_result(sqrt_result)

      # Call 2: sin(1.0)
      call("Math.sin/1",
        module: "math",
        function: "sin",
        args: [1.0]
      )

      sin_result = Math.sin(1.0)
      print_result(sin_result)

      # Call 3: cos(0.0)
      call("Math.cos/1",
        module: "math",
        function: "cos",
        args: [0.0]
      )

      cos_result = Math.cos(0.0)
      print_result(cos_result)

      IO.puts("")
      IO.puts("── Summary ─────────────────────────────────────────────────")

      with {:ok, sqrt} <- sqrt_result,
           {:ok, sin} <- sin_result,
           {:ok, cos} <- cos_result do
        IO.puts("  sqrt(2)      = #{sqrt}")
        IO.puts("  sin(1.0)     = #{sin}")
        IO.puts("  cos(0.0)     = #{cos}")
      else
        error ->
          IO.puts("  Some calls failed: #{inspect(error)}")
      end
    else
      IO.puts("  Math module not available. Run `mix compile`.")
    end

    IO.puts("")
  end

  defp call(title, opts) do
    IO.puts("┌─ #{title}")
    IO.puts("│  Python module:   #{opts[:module]}")
    IO.puts("│  Python function: #{opts[:function]}")
    IO.puts("│  Arguments:       #{inspect(opts[:args])}")
    IO.puts("│")
  end

  defp print_result({:ok, value}) do
    IO.puts("└─ Result: {:ok, #{inspect(value)}}")
    IO.puts("")
  end

  defp print_result({:error, reason}) do
    IO.puts("└─ Result: {:error, #{inspect(reason)}}")
    IO.puts("")
  end

  defp print_result(other) do
    IO.puts("└─ Result: #{inspect(other)}")
    IO.puts("")
  end
end
