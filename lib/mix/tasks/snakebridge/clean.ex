defmodule Mix.Tasks.Snakebridge.Clean do
  use Mix.Task

  @shortdoc "Remove all generated adapters"

  @moduledoc """
  Removes all generated Python library adapters.

  This task removes all generated adapter directories and clears the registry.

  ## Usage

      mix snakebridge.clean
      mix snakebridge.clean --yes

  ## Options

    * `--yes` - Skip confirmation prompt

  ## Examples

      # Remove all adapters (will ask for confirmation)
      mix snakebridge.clean

      # Remove all adapters without confirmation
      mix snakebridge.clean --yes

  ## What it does

  1. Lists all generated adapters from the registry
  2. Asks for confirmation (unless --yes is provided)
  3. Removes all adapter directories
  4. Clears the registry
  5. Shows summary of what was removed

  ## Requirements

  - Registry file must exist at `priv/snakebridge/registry.json`
  """

  @registry_path "priv/snakebridge/registry.json"

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [yes: :boolean])

    # Read registry
    registry = read_registry()
    libraries = registry["libraries"]

    if map_size(libraries) == 0 do
      Mix.shell().info("No generated adapters to clean.")
      exit({:shutdown, 0})
    end

    # Show what will be removed
    Mix.shell().info("This will remove all generated adapters:")
    Mix.shell().info("")

    for {lib, info} <- Enum.sort(libraries) do
      functions = get_in(info, ["stats", "functions"]) || 0
      Mix.shell().info("  - #{lib} (#{functions} functions)")
    end

    Mix.shell().info("")

    # Ask for confirmation unless --yes flag is provided
    unless opts[:yes] do
      unless Mix.shell().yes?("Continue? [y/N]") do
        Mix.shell().info("Cancelled.")
        exit({:shutdown, 0})
      end
    end

    Mix.shell().info("")

    # Remove each library
    count =
      Enum.reduce(Enum.sort(libraries), 0, fn {lib, info}, acc ->
        Mix.shell().info("Removing #{lib}...")
        adapter_path = info["path"]

        if File.dir?(adapter_path) do
          File.rm_rf!(adapter_path)
        end

        acc + 1
      end)

    # Clear registry
    cleared_registry = %{
      "version" => "2.1",
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "libraries" => %{}
    }

    write_registry(cleared_registry)

    Mix.shell().info("")
    Mix.shell().info("Removed #{count} libraries.")
    Mix.shell().info("Registry cleared.")
  end

  defp read_registry do
    if File.exists?(@registry_path) do
      @registry_path
      |> File.read!()
      |> Jason.decode!()
    else
      # Create empty registry if it doesn't exist
      %{
        "version" => "2.1",
        "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "libraries" => %{}
      }
    end
  end

  defp write_registry(registry) do
    # Ensure directory exists
    File.mkdir_p!(Path.dirname(@registry_path))

    # Write registry
    @registry_path
    |> File.write!(Jason.encode!(registry, pretty: true))
  end
end
