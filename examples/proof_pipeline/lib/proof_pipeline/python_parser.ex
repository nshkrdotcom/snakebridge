defmodule ProofPipeline.PythonParser do
  @moduledoc false

  def __snakebridge_python_name__, do: "proof_pipeline_parser"

  @spec parse_expr(String.t()) :: {:ok, term()} | {:error, Snakepit.Error.t()}
  def parse_expr(expr) do
    SnakeBridge.Runtime.call(__MODULE__, :parse_expr_implicit, [expr])
  end
end
