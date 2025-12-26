defmodule Demo do
  @moduledoc """
  Run with: mix run -e Demo.run
  """

  def run do
    IO.puts("""
    ╔═══════════════════════════════════════════════════════════╗
    ║            ProofPipeline - SnakeBridge Demo               ║
    ╚═══════════════════════════════════════════════════════════╝
    """)

    input = ProofPipeline.sample_input()

    if live?() do
      IO.puts("Running live pipeline (requires Python libs installed)...")

      case ProofPipeline.run(input) do
        {:ok, result} ->
          IO.inspect(result, label: "Pipeline result")

        {:error, reason} ->
          IO.puts("Pipeline failed: #{inspect(reason)}")
      end
    else
      IO.puts("Dry run plan (set PROOF_PIPELINE_LIVE=1 to execute):")

      ProofPipeline.plan(input)
      |> Enum.each(fn step ->
        IO.puts(
          "  - #{step.step}: #{inspect(step.library)}.#{step.function}/#{length(step.args)}"
        )
      end)
    end
  end

  defp live? do
    case System.get_env("PROOF_PIPELINE_LIVE") do
      nil -> false
      value -> value in ["1", "true", "TRUE", "yes", "YES"]
    end
  end
end
