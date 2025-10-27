defmodule Mix.Tasks.Snakebridge.Generate do
  @moduledoc """
  Generate Elixir modules from SnakeBridge configurations.

  ## Usage

      mix snakebridge.generate [CONFIG_PATHS...]

  ## Arguments

    * `CONFIG_PATHS` - Optional list of config files to generate (default: all in config/snakebridge/)

  ## Examples

      # Generate from all configs
      mix snakebridge.generate

      # Generate from specific configs
      mix snakebridge.generate config/snakebridge/dspy.exs config/snakebridge/langchain.exs
  """

  @shortdoc "Generate Elixir modules from SnakeBridge configs"

  use Mix.Task

  alias SnakeBridge.Generator

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    config_files =
      case args do
        [] -> find_all_configs()
        paths -> paths
      end

    if Enum.empty?(config_files) do
      Mix.shell().info("No config files found")
      Mix.shell().info("Run 'mix snakebridge.discover MODULE' first")
      return()
    end

    Mix.shell().info("Generating modules from configs...")
    Mix.shell().info("")

    Enum.each(config_files, fn path ->
      generate_from_config(path)
    end)
  end

  defp find_all_configs do
    case File.ls("config/snakebridge") do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".exs"))
        |> Enum.map(&Path.join("config/snakebridge", &1))

      {:error, :enoent} ->
        []
    end
  end

  defp generate_from_config(path) do
    relative_path = Path.relative_to_cwd(path)

    try do
      {config, _bindings} = Code.eval_file(path)

      case Generator.generate_all(config) do
        {:ok, modules} ->
          Mix.shell().info("✓ #{relative_path}")

          Enum.each(modules, fn module ->
            Mix.shell().info("  - #{inspect(module)}")
          end)

        {:error, reason} ->
          Mix.shell().error("✗ #{relative_path}")
          Mix.shell().error("  - #{inspect(reason)}")
      end
    rescue
      e ->
        Mix.shell().error("✗ #{relative_path}")
        Mix.shell().error("  - Failed to load: #{Exception.message(e)}")
    end
  end

  defp return, do: nil
end
