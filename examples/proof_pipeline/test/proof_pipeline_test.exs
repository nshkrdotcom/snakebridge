defmodule ProofPipelineTest do
  use ExUnit.Case

  test "plan includes all three libraries" do
    plan = ProofPipeline.plan(ProofPipeline.sample_input())
    libraries = plan |> Enum.map(& &1.library) |> MapSet.new()

    assert Sympy in libraries
    assert PyLatexEnc.Latexencode in libraries
    assert PyLatexEnc.Latexwalker.LatexWalker in libraries
    assert MathVerify in libraries
  end

  test "sample input has expected keys" do
    input = ProofPipeline.sample_input()
    assert Map.has_key?(input, :prompt_latex)
    assert Map.has_key?(input, :student_latex)
    assert Map.has_key?(input, :gold_latex)
  end
end
