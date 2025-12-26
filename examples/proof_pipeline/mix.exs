defmodule ProofPipeline.MixProject do
  use Mix.Project

  def project do
    [
      app: :proof_pipeline,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:snakebridge] ++ Mix.compilers()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:snakebridge,
       path: "../..",
       libraries: [
         sympy: [version: "~> 1.12", module_name: Sympy],
         pylatexenc: [version: "~> 2.10", module_name: PyLatexEnc, submodules: true],
         math_verify: [version: "~> 0.1", module_name: MathVerify]
       ]},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
