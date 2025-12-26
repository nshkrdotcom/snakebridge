defmodule ProofPipeline do
  @moduledoc """
  Orchestrates a proof-grading pipeline across SymPy, pylatexenc, and math_verify.

  This module builds a multi-step flow:
  1. Parse LaTeX into nodes (pylatexenc)
  2. Normalize and simplify (SymPy)
  3. Verify and grade (math_verify)

  The live runtime path is optional. Use `Demo.run/0` to see the dry plan.
  """

  @type input :: %{
          prompt_latex: String.t(),
          student_latex: String.t(),
          gold_latex: String.t()
        }

  @spec sample_input() :: input()
  def sample_input do
    %{
      prompt_latex: "\\frac{d}{dx} x^2",
      student_latex: "2x",
      gold_latex: "2 x"
    }
  end

  @spec plan(input()) :: [map()]
  def plan(%{student_latex: student, gold_latex: gold}) do
    expr = "<sympy_expr>"
    normalized = "<normalized_latex>"

    [
      %{
        step: :new_latex_walker,
        library: PyLatexEnc.Latexwalker.LatexWalker,
        function: :new,
        args: [student]
      },
      %{
        step: :parse_nodes,
        library: PyLatexEnc.Latexwalker.LatexWalker,
        function: :get_latex_nodes,
        args: [student]
      },
      %{step: :sympify, library: Sympy, function: :sympify, args: [student]},
      %{step: :simplify, library: Sympy, function: :simplify, args: [expr]},
      %{step: :render_latex, library: Sympy, function: :latex, args: [expr]},
      %{
        step: :normalize_latex,
        library: PyLatexEnc.Latexencode,
        function: :unicode_to_latex,
        args: [normalized]
      },
      %{step: :verify, library: MathVerify, function: :verify, args: [gold, normalized]},
      %{step: :parse, library: MathVerify, function: :parse, args: [normalized]},
      %{step: :grade, library: MathVerify, function: :grade, args: [gold, normalized]}
    ]
  end

  @spec run(input()) :: {:ok, map()} | {:error, term()}
  def run(%{student_latex: student, gold_latex: gold} = input) do
    with {:ok, walker} <- PyLatexEnc.Latexwalker.LatexWalker.new(student),
         {:ok, nodes} <- PyLatexEnc.Latexwalker.LatexWalker.get_latex_nodes(walker),
         {:ok, expr} <- Sympy.sympify(student),
         {:ok, simplified} <- Sympy.simplify(expr),
         {:ok, rendered} <- Sympy.latex(simplified),
         {:ok, normalized} <- PyLatexEnc.Latexencode.unicode_to_latex(rendered),
         {:ok, verdict} <- MathVerify.verify(gold, normalized),
         {:ok, parsed} <- MathVerify.parse(normalized),
         {:ok, grade} <- MathVerify.grade(gold, normalized) do
      {:ok,
       %{
         input: input,
         nodes: nodes,
         simplified: simplified,
         rendered: rendered,
         normalized: normalized,
         parsed: parsed,
         verdict: verdict,
         grade: grade
       }}
    end
  end
end
