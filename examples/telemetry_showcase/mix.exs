defmodule TelemetryShowcase.MixProject do
  use Mix.Project

  def project do
    [
      app: :telemetry_showcase,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Add SnakeBridge compiler
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
      # SnakeBridge with math library for demo (snakepit comes transitively)
      {:snakebridge, path: "../..", libraries: [math: :stdlib, json: :stdlib]},
      # Telemetry (transitive, but explicit for the showcase)
      {:telemetry, "~> 1.2"}
    ]
  end
end
