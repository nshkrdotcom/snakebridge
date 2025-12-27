defmodule StrictProject.MixProject do
  use Mix.Project

  def project do
    [
      app: :strict_project,
      version: "0.1.0",
      elixir: "~> 1.14",
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
      {:snakebridge,
       path: "../../..",
       libraries: [
         numpy: [version: "~> 1.26", module_name: Numpy]
       ]}
    ]
  end
end
