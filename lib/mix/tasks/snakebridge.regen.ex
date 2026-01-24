defmodule Mix.Tasks.Snakebridge.Regen do
  @shortdoc "Regenerate SnakeBridge wrappers"
  @moduledoc """
  Forces SnakeBridge regeneration without relying on compile-time cache checks.

  ## Usage

      mix snakebridge.regen

  ## Options

      --clean    Remove generated files and metadata before regeneration
      --verbose  Print cleaned paths
  """

  use Mix.Task

  alias SnakeBridge.Compiler.Pipeline

  @impl true
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args, switches: [clean: :boolean, verbose: :boolean])

    Mix.Task.run("loadconfig")
    config = SnakeBridge.Config.load()

    if opts[:clean] do
      clean_artifacts(config, opts[:verbose] == true)
    end

    Pipeline.run(config)
  end

  defp clean_artifacts(config, verbose?) do
    paths = [
      config.metadata_dir,
      config.generated_dir,
      registry_path(),
      "snakebridge.lock"
    ]

    Enum.each(paths, &remove_path(&1, verbose?))
  end

  defp registry_path do
    Application.get_env(:snakebridge, :registry_path) ||
      Path.join([File.cwd!(), "priv", "snakebridge", "registry.json"])
  end

  defp remove_path(nil, _verbose?), do: :ok

  defp remove_path(path, verbose?) do
    if File.exists?(path) do
      File.rm_rf(path)
      if verbose?, do: Mix.shell().info("Removed #{path}")
    else
      if verbose?, do: Mix.shell().info("Skipped missing #{path}")
    end
  end
end
