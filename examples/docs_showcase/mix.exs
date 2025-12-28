defmodule DocsShowcase.MixProject do
  use Mix.Project

  def project do
    [
      app: :docs_showcase,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:snakebridge, path: "../.."}
    ]
  end
end
