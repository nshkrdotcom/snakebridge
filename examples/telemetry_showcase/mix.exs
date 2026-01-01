defmodule TelemetryShowcase.MixProject do
  use Mix.Project

  def project do
    [
      app: :telemetry_showcase,
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
      {:telemetry, "~> 1.2"}
    ]
  end

  defp python_deps do
    [
      {:math, :stdlib},
      {:json, :stdlib}
    ]
  end
end
