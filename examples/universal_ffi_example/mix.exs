defmodule UniversalFfiExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :universal_ffi_example,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [{:snakebridge, path: "../.."}]
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
