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
      compilers: [:snakebridge] ++ Mix.compilers(),
      docs: docs()
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
    [
      {:math, :stdlib, python_name: "math", module_name: Math},
      {:pathlib, :stdlib, python_name: "pathlib", module_name: Pathlib},
      {:numpy, :stdlib,
       python_name: "numpy", module_name: Numpy, include: ["nan", "array", "ndarray"]}
    ]
  end

  defp docs do
    groups =
      if Code.ensure_loaded?(SnakeBridge.Docs) and
           function_exported?(SnakeBridge.Docs, :groups_for_modules, 0) do
        SnakeBridge.Docs.groups_for_modules()
      else
        []
      end

    nests =
      if Code.ensure_loaded?(SnakeBridge.Docs) and
           function_exported?(SnakeBridge.Docs, :nest_modules_by_prefix, 0) do
        SnakeBridge.Docs.nest_modules_by_prefix()
      else
        []
      end

    [
      groups_for_modules: groups,
      nest_modules_by_prefix: nests
    ]
  end
end
