#!/usr/bin/env elixir
#
# Math-Verify Manifest Example
# Run with: mix run --no-start examples/manifest_math_verify.exs
#

Code.require_file(Path.join(__DIR__, "support.exs"))
SnakeBridge.Examples.Support.start!()

IO.puts("\nSnakeBridge Example: Math-Verify\n")
IO.puts(String.duplicate("=", 60))

case SnakeBridge.Manifest.Loader.load([:math_verify], []) do
  {:ok, _modules} ->
    IO.puts("Loaded manifest: math_verify")

    parse_text = "The answer is $x^2$ and $x**2$"
    {:ok, parsed} = SnakeBridge.MathVerify.parse(%{text: parse_text})
    IO.puts("parse: #{inspect(parsed)}")

    gold = "x^2"
    answer_same = "x^2"
    answer_diff = "x^3"

    {:ok, verified_same} = SnakeBridge.MathVerify.verify(%{gold: gold, answer: answer_same})
    IO.puts("verify: gold=#{gold} answer=#{answer_same} -> #{inspect(verified_same)}")

    {:ok, verified_diff} = SnakeBridge.MathVerify.verify(%{gold: gold, answer: answer_diff})
    IO.puts("verify: gold=#{gold} answer=#{answer_diff} -> #{inspect(verified_diff)}")

    {:ok, graded_same} = SnakeBridge.MathVerify.grade(%{gold: gold, answer: answer_same})
    IO.puts("grade: gold=#{gold} answer=#{answer_same} -> #{inspect(graded_same)}")

    IO.puts("\nMath-Verify example complete")

  {:error, errors} ->
    IO.puts("Failed to load math-verify manifest:")
    IO.inspect(errors)
    System.halt(1)
end
