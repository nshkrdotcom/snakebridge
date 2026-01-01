defmodule ClassResolutionExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :class_resolution_example,
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
    base = [
      {:math, :stdlib, python_name: "math", module_name: Math},
      {:pathlib, :stdlib, python_name: "pathlib", module_name: Pathlib}
    ]

    if System.get_env("SNAKEBRIDGE_EXAMPLE_NUMPY") == "1" do
      base ++ [{:numpy, :stdlib, python_name: "numpy", module_name: Numpy}]
    else
      base
    end
  end
end
