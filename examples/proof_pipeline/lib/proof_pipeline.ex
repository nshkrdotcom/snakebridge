defmodule ProofPipeline do
  @moduledoc """
  Orchestrates a proof-grading pipeline across SymPy, pylatexenc, and math_verify.

  This module builds a multi-step flow:
  1. Parse LaTeX into nodes (pylatexenc)
  2. Normalize and simplify (SymPy)
  3. Verify with math_verify
  Use `Demo.run/0` to execute the live pipeline.
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
    rendered = "<rendered_latex>"

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
      %{
        step: :parse_expr,
        library: ProofPipeline.PythonParser,
        function: :parse_expr,
        args: [student]
      },
      %{step: :simplify, library: Sympy, function: :simplify, args: [expr]},
      %{step: :render_latex, library: Sympy, function: :latex, args: [expr]},
      %{step: :verify, library: MathVerify, function: :verify, args: [gold, rendered]},
      %{step: :parse, library: MathVerify, function: :parse, args: [rendered]}
    ]
  end

  @spec run(input()) :: {:ok, map()} | {:error, term()}
  def run(%{student_latex: student, gold_latex: gold} = input) do
    math_verify_runtime = [__runtime__: [thread_sensitive: true]]

    with {:ok, walker} <- PyLatexEnc.Latexwalker.LatexWalker.new(student),
         {:ok, nodes} <- PyLatexEnc.Latexwalker.LatexWalker.get_latex_nodes(walker),
         {:ok, expr} <- ProofPipeline.PythonParser.parse_expr(student),
         {:ok, simplified} <- Sympy.simplify(expr),
         {:ok, rendered} <- Sympy.latex(simplified),
         {:ok, verdict} <- MathVerify.verify(gold, rendered, math_verify_runtime),
         {:ok, parsed} <- MathVerify.parse(rendered, math_verify_runtime) do
      {:ok,
       %{
         input: input,
         nodes: nodes,
         simplified: simplified,
         rendered: rendered,
         normalized: rendered,
         parsed: parsed,
         verdict: verdict
       }}
    end
  end
end
