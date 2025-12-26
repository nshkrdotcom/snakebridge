defmodule MathDemo.MixProject do
  use Mix.Project

  def project do
    [
      app: :math_demo,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Add SnakeBridge compiler - this is the key line!
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
      # In a real project, you'd use: {:snakebridge, "~> 3.0", libraries: [...]}
      # For this example, we reference the parent directory
      {:snakebridge, path: "../..", libraries: [json: :stdlib, math: :stdlib]},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
