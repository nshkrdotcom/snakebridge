defmodule Demo do
  require SnakeBridge

  @moduledoc """
  Run with: mix run --no-start -e Demo.run
  """

  alias SnakeBridge.Examples

  def run do
    SnakeBridge.script do
      Examples.reset_failures()

      IO.puts("""
      ╔═══════════════════════════════════════════════════════════╗
      ║            ProofPipeline - SnakeBridge Demo               ║
      ╚═══════════════════════════════════════════════════════════╝
      """)

      input = ProofPipeline.sample_input()

      IO.puts("Input:")
      IO.puts("  prompt_latex:  #{inspect(input.prompt_latex)}")
      IO.puts("  student_latex: #{inspect(input.student_latex)}")
      IO.puts("  gold_latex:    #{inspect(input.gold_latex)}")
      IO.puts("")

      IO.puts("Running live pipeline (requires Python libs installed)...")
      IO.puts("")
      IO.puts(String.duplicate("─", 60))

      run_verbose_pipeline(input)

      Examples.assert_no_failures!()
    end
    |> Examples.assert_script_ok()
  end

  defp run_verbose_pipeline(%{student_latex: student, gold_latex: gold} = input) do
    math_verify_runtime = [__runtime__: [thread_sensitive: true]]

    # Step 1: Create LatexWalker
    step("1. PyLatexEnc.Latexwalker.LatexWalker.new/1",
      module: "pylatexenc.latexwalker",
      function: "LatexWalker",
      args: [student]
    )

    walker_result = PyLatexEnc.Latexwalker.LatexWalker.new(student)
    print_result(walker_result)

    with {:ok, walker} <- walker_result do
      # Step 2: Get latex nodes
      step("2. PyLatexEnc.Latexwalker.LatexWalker.get_latex_nodes/1",
        module: "pylatexenc.latexwalker",
        function: "get_latex_nodes",
        args: ["<walker_ref>"]
      )

      nodes_result = PyLatexEnc.Latexwalker.LatexWalker.get_latex_nodes(walker)
      print_result(nodes_result)

      with {:ok, nodes} <- nodes_result do
        # Step 3: Parse expression with SymPy
        step("3. ProofPipeline.PythonParser.parse_expr/1",
          module: "sympy.parsing.latex",
          function: "parse_latex",
          args: [student]
        )

        expr_result = ProofPipeline.PythonParser.parse_expr(student)
        print_result(expr_result)

        with {:ok, expr} <- expr_result do
          # Step 4: Simplify with SymPy
          step("4. Sympy.simplify/1",
            module: "sympy",
            function: "simplify",
            args: [expr]
          )

          simplified_result = Sympy.simplify(expr)
          print_result(simplified_result)

          with {:ok, simplified} <- simplified_result do
            # Step 5: Render back to LaTeX
            step("5. Sympy.latex/1",
              module: "sympy",
              function: "latex",
              args: [simplified]
            )

            rendered_result = Sympy.latex(simplified)
            print_result(rendered_result)

            with {:ok, rendered} <- rendered_result do
              # Step 6: Verify with math_verify
              step("6. MathVerify.verify/2",
                module: "math_verify",
                function: "verify",
                args: [gold, rendered]
              )

              verdict_result = MathVerify.verify(gold, rendered, math_verify_runtime)
              print_result(verdict_result)

              with {:ok, verdict} <- verdict_result do
                # Step 7: Parse rendered expression
                step("7. MathVerify.parse/1",
                  module: "math_verify",
                  function: "parse",
                  args: [rendered]
                )

                parsed_result = MathVerify.parse(rendered, math_verify_runtime)
                print_result(parsed_result)

                with {:ok, parsed} <- parsed_result do
                  IO.puts("")
                  IO.puts(String.duplicate("═", 60))
                  IO.puts("PIPELINE COMPLETE")
                  IO.puts(String.duplicate("═", 60))

                  final = %{
                    input: input,
                    nodes: nodes,
                    simplified: simplified,
                    rendered: rendered,
                    normalized: rendered,
                    parsed: parsed,
                    verdict: verdict
                  }

                  IO.puts("")
                  IO.puts("Final Result:")
                  IO.inspect(final, pretty: true, limit: :infinity)

                  {:ok, final}
                end
              end
            end
          end
        end
      end
    end
  end

  defp step(title, opts) do
    IO.puts("")
    IO.puts("┌─ #{title}")
    IO.puts("│  Python module:   #{opts[:module]}")
    IO.puts("│  Python function: #{opts[:function]}")
    IO.puts("│  Arguments:       #{inspect(opts[:args])}")
    IO.puts("│")
  end

  defp print_result({:ok, value}) do
    value_str = inspect(value, limit: 100, printable_limit: 200)

    if String.length(value_str) > 60 do
      IO.puts("└─ Result: {:ok,")
      IO.puts("     #{value_str}}")
    else
      IO.puts("└─ Result: {:ok, #{value_str}}")
    end
  end

  defp print_result({:error, reason}) do
    IO.puts("└─ Result: {:error, #{inspect(reason)}}")
    Examples.record_failure()
  end

  defp print_result(other) do
    IO.puts("└─ Result: #{inspect(other)}")
  end
end
