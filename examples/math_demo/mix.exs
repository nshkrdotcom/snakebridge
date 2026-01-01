defmodule MathDemo.MixProject do
  use Mix.Project

  def project do
    [
      app: :math_demo,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      python_deps: python_deps(),
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
      {:snakebridge, path: "../.."},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp python_deps do
    [
      {:json, :stdlib},
      {:math, :stdlib}
    ]
  end
end
