defmodule Mix.Tasks.Compile.Snakebridge do
  @moduledoc """
  Mix compiler that runs the SnakeBridge pre-pass (scan → introspect → generate).
  """

  use Mix.Task.Compiler

  alias SnakeBridge.Compiler.Pipeline
  alias SnakeBridge.Config

  @impl Mix.Task.Compiler
  def run(_args) do
    Mix.Task.run("loadconfig")

    if skip_generation?() do
      {:ok, []}
    else
      config = Config.load()
      Pipeline.run(config)
    end
  end

  @impl Mix.Task.Compiler
  def manifests do
    Mix.Task.run("loadconfig")
    config = Config.load()

    [
      Path.join(config.metadata_dir, "manifest.json"),
      "snakebridge.lock"
    ]
  end

  @doc false
  defdelegate verify_generated_files_exist!(config), to: Pipeline

  @doc false
  defdelegate verify_symbols_present!(config, manifest), to: Pipeline

  defp skip_generation? do
    case System.get_env("SNAKEBRIDGE_SKIP") do
      nil -> false
      value -> value in ["1", "true", "TRUE", "yes", "YES"]
    end
  end
end
