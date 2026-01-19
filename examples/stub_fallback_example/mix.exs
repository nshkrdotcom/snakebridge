defmodule StubFallbackExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :stub_fallback_example,
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
      {:stub_fallback, :stdlib,
       python_name: "stub_fallback_example", module_name: StubFallbackExample, generate: :all}
    ]
  end
end
