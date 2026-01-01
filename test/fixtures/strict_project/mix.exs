defmodule StrictProject.MixProject do
  use Mix.Project

  def project do
    [
      app: :strict_project,
      version: "0.1.0",
      elixir: "~> 1.14",
      deps: deps(),
      python_deps: python_deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:snakebridge, path: "../../.."}
    ]
  end

  defp python_deps do
    [
      {:numpy, "~> 1.26", module_name: Numpy}
    ]
  end
end
