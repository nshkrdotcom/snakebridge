#!/usr/bin/env elixir
#
# SymPy Manifest Example
# Run with: mix run --no-start examples/manifest_sympy.exs
#

Code.require_file(Path.join(__DIR__, "support.exs"))
SnakeBridge.Examples.Support.start!()

IO.puts("\nSnakeBridge Example: SymPy\n")
IO.puts(String.duplicate("=", 60))

case SnakeBridge.Manifest.Loader.load([:sympy], []) do
  {:ok, _modules} ->
    IO.puts("Loaded manifest: sympy")

    expr = "sin(x)**2 + cos(x)**2"
    {:ok, simplified} = SnakeBridge.SymPy.simplify(%{expr: expr})

    IO.puts("simplify: #{expr} -> #{simplified}")

    solve_expr = "x**2 - 1"
    {:ok, roots} = SnakeBridge.SymPy.solve(%{expr: solve_expr, symbol: "x"})
    IO.puts("solve: #{solve_expr} (symbol: x) -> #{inspect(roots)}")

    free_expr = "x*y + 1"
    {:ok, symbols} = SnakeBridge.SymPy.free_symbols(%{expr: free_expr})
    IO.puts("free_symbols: #{free_expr} -> #{inspect(symbols)}")

    IO.puts("\nSymPy example complete")

  {:error, errors} ->
    IO.puts("Failed to load SymPy manifest:")
    IO.inspect(errors)
    System.halt(1)
end
