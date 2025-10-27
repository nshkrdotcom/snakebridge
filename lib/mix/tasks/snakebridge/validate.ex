defmodule Mix.Tasks.Snakebridge.Validate do
  @moduledoc """
  Validates all SnakeBridge configuration files.

  ## Usage

      mix snakebridge.validate [PATH]

  ## Arguments

    * `PATH` - Optional path to specific config file (default: validates all in config/snakebridge/)

  ## Examples

      # Validate all configs
      mix snakebridge.validate

      # Validate specific config
      mix snakebridge.validate config/snakebridge/dspy.exs
  """

  @shortdoc "Validate SnakeBridge configuration files"

  use Mix.Task

  alias SnakeBridge.Config

  @impl Mix.Task
  def run(args) do
    config_files =
      case args do
        [] -> find_all_configs()
        [path | _] -> [path]
      end

    if Enum.empty?(config_files) do
      Mix.shell().info("No config files found in config/snakebridge/")
      Mix.shell().info("Run 'mix snakebridge.discover MODULE' to generate configs")
      return()
    end

    Mix.shell().info("Validating configs in config/snakebridge/...")
    Mix.shell().info("")

    results =
      Enum.map(config_files, fn path ->
        validate_config_file(path)
      end)

    # Report summary
    valid_count = Enum.count(results, &(&1 == :ok))
    invalid_count = Enum.count(results, &match?({:error, _}, &1))

    Mix.shell().info("")

    if invalid_count == 0 do
      Mix.shell().info("✓ All #{valid_count} config(s) validated successfully")
    else
      Mix.raise("#{invalid_count} config(s) failed validation")
    end
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

  defp validate_config_file(path) do
    relative_path = Path.relative_to_cwd(path)

    try do
      {config, _bindings} = Code.eval_file(path)

      case Config.validate(config) do
        {:ok, _valid_config} ->
          Mix.shell().info("✓ #{relative_path}")
          :ok

        {:error, errors} ->
          Mix.shell().error("✗ #{relative_path}")

          Enum.each(errors, fn error ->
            Mix.shell().error("  - #{error}")
          end)

          {:error, errors}
      end
    rescue
      e ->
        Mix.shell().error("✗ #{relative_path}")
        Mix.shell().error("  - Failed to load file: #{Exception.message(e)}")
        {:error, Exception.message(e)}
    end
  end

  defp return, do: nil
end
