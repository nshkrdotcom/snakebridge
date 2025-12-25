defmodule Mix.Tasks.Snakebridge.List do
  use Mix.Task

  @shortdoc "List generated libraries"

  @moduledoc """
  Lists all generated Python library adapters.

  This task shows a table of all generated adapters with their statistics.

  ## Usage

      mix snakebridge.list

  ## Examples

      # List all generated adapters
      mix snakebridge.list

  ## Output

  Shows a table with the following columns:
  - Library: The library name
  - Functions: Number of functions
  - Classes: Number of classes
  - Path: Path to the adapter directory

  ## Requirements

  - Registry file must exist at `priv/snakebridge/registry.json`
  """

  @registry_path "priv/snakebridge/registry.json"

  @impl Mix.Task
  def run(_args) do
    # Read registry
    registry = read_registry()
    libraries = registry["libraries"]

    if map_size(libraries) == 0 do
      Mix.shell().info("No generated adapters found.")
      Mix.shell().info("")
      Mix.shell().info("Run `mix snakebridge.gen <library>` to generate an adapter.")
      exit({:shutdown, 0})
    end

    Mix.shell().info("Generated libraries:")
    Mix.shell().info("")

    # Print table header
    Mix.shell().info(format_row("Library", "Functions", "Classes", "Path"))
    Mix.shell().info(String.duplicate("-", 80))

    # Print each library
    for {lib, info} <- Enum.sort(libraries) do
      functions = get_in(info, ["stats", "functions"]) || 0
      classes = get_in(info, ["stats", "classes"]) || 0
      path = info["path"] || ""

      Mix.shell().info(format_row(lib, to_string(functions), to_string(classes), path))
    end

    Mix.shell().info("")
    Mix.shell().info("Total: #{map_size(libraries)} libraries")
  end

  defp read_registry do
    if File.exists?(@registry_path) do
      @registry_path
      |> File.read!()
      |> Jason.decode!()
    else
      # Return empty registry if it doesn't exist
      %{
        "version" => "2.1",
        "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "libraries" => %{}
      }
    end
  end

  defp format_row(library, functions, classes, path) do
    lib_width = 15
    func_width = 10
    class_width = 8

    lib = String.pad_trailing(library, lib_width)
    func = String.pad_trailing(functions, func_width)
    cls = String.pad_trailing(classes, class_width)

    "#{lib} #{func} #{cls} #{path}"
  end
end
