#!/usr/bin/env elixir
#
# PyLatexEnc Manifest Example
# Run with: mix run --no-start examples/manifest_pylatexenc.exs
#

Code.require_file(Path.join(__DIR__, "support.exs"))
SnakeBridge.Examples.Support.start!()

IO.puts("\nSnakeBridge Example: PyLatexEnc\n")
IO.puts(String.duplicate("=", 60))

case SnakeBridge.Manifest.Loader.load([:pylatexenc], []) do
  {:ok, _modules} ->
    IO.puts("Loaded manifest: pylatexenc")

    latex_expr = "\\alpha + \\beta"
    {:ok, text} = SnakeBridge.PyLatexEnc.latex_to_text(%{latex: latex_expr})
    IO.puts("latex_to_text: #{latex_expr} -> #{text}")

    parse_expr = "\\frac{1}{2}"
    {:ok, nodes} = SnakeBridge.PyLatexEnc.parse(%{latex: parse_expr})

    first_type =
      case nodes do
        [node | _] -> Map.get(node, "type") || Map.get(node, :type) || "unknown"
        [] -> "none"
      end

    IO.puts("parse: #{parse_expr} -> nodes=#{length(nodes)} first_type=#{first_type}")

    unicode_text = "\u03b1 + \u03b2"
    {:ok, latex} = SnakeBridge.PyLatexEnc.unicode_to_latex(%{text: unicode_text})
    IO.puts("unicode_to_latex: #{unicode_text} -> #{latex}")

    IO.puts("\nPyLatexEnc example complete")

  {:error, errors} ->
    IO.puts("Failed to load pylatexenc manifest:")
    IO.inspect(errors)
    System.halt(1)
end
