defmodule ErrorShowcase.MixProject do
  use Mix.Project

  def project do
    [
      app: :error_showcase,
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
      # SnakeBridge for error translation (snakepit comes transitively)
      {:snakebridge, path: "../.."}
    ]
  end
end
