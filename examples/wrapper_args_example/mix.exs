defmodule WrapperArgsExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :wrapper_args_example,
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
      {:snakebridge, path: "../.."}
    ]
  end

  defp python_deps do
    [
      {:wrapper_args, :stdlib,
       python_name: "wrapper_args_example",
       module_name: WrapperArgs,
       include: ["mean", "join_values"]}
    ]
  end
end
