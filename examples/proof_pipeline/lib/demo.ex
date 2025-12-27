defmodule Demo do
  @moduledoc """
  Run with: mix run -e Demo.run
  """

  def run do
    Snakepit.run_as_script(fn ->
      IO.puts("""
      ╔═══════════════════════════════════════════════════════════╗
      ║            ProofPipeline - SnakeBridge Demo               ║
      ╚═══════════════════════════════════════════════════════════╝
      """)

      input = ProofPipeline.sample_input()

      IO.puts("Running live pipeline (requires Python libs installed)...")

      case ProofPipeline.run(input) do
        {:ok, result} ->
          IO.inspect(result, label: "Pipeline result")

        {:error, reason} ->
          IO.puts("Pipeline failed: #{inspect(reason)}")
      end
    end)
    |> case do
      {:error, reason} ->
        IO.puts("Snakepit script failed: #{inspect(reason)}")

      _ ->
        :ok
    end
  end
end
