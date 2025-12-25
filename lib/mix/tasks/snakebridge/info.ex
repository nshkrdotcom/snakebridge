defmodule Mix.Tasks.Snakebridge.Info do
  use Mix.Task

  @shortdoc "Show details about a library"

  @moduledoc """
  Shows detailed information about a generated library adapter.

  This task displays comprehensive information about a generated adapter including
  Python module details, version, files, statistics, and usage examples.

  ## Usage

      mix snakebridge.info <library>

  ## Examples

      # Show information about the numpy adapter
      mix snakebridge.info numpy

      # Show information about the json adapter
      mix snakebridge.info json

  ## Output

  Shows:
  - Python module name and version
  - Elixir module name
  - Generation timestamp
  - Adapter path
  - Statistics (functions, classes, submodules)
  - List of generated files
  - Quick start example

  ## Requirements

  - Registry file must exist at `priv/snakebridge/registry.json`
  - Library must be in the registry
  """

  @registry_path "priv/snakebridge/registry.json"

  @impl Mix.Task
  def run([]) do
    raise Mix.Error, "Library name required\n\nUsage: mix snakebridge.info <library>"
  end

  def run([library | _rest]) do
    # Read registry
    registry = read_registry()

    # Check if library exists in registry
    unless Map.has_key?(registry["libraries"], library) do
      Mix.shell().error("Library '#{library}' not found.")
      Mix.shell().info("")
      Mix.shell().info("Available libraries:")

      if map_size(registry["libraries"]) == 0 do
        Mix.shell().info("  (none)")
        Mix.shell().info("")
        Mix.shell().info("Run `mix snakebridge.gen <library>` to generate an adapter.")
      else
        for lib <- Map.keys(registry["libraries"]) |> Enum.sort() do
          Mix.shell().info("  - #{lib}")
        end
      end

      exit({:shutdown, 1})
    end

    # Get library info
    info = registry["libraries"][library]

    # Display information
    Mix.shell().info("")
    Mix.shell().info("Library: #{library}")
    Mix.shell().info("=" |> String.duplicate(80))
    Mix.shell().info("")

    # Python module info
    python_module = info["python_module"] || library
    python_version = info["python_version"] || "unknown"
    Mix.shell().info("Python module: #{python_module} (version #{python_version})")

    # Elixir module
    elixir_module = info["elixir_module"] || Macro.camelize(library)
    Mix.shell().info("Elixir module: #{elixir_module}")

    # Generated timestamp
    if generated_at = info["generated_at"] do
      # Format: "2024-12-24T14:00:00Z" -> "2024-12-24 14:00:00"
      formatted_time = String.replace(generated_at, ~r/T(\d{2}:\d{2}:\d{2}).*/, " \\1")
      Mix.shell().info("Generated: #{formatted_time}")
    end

    Mix.shell().info("")

    # Path
    adapter_path = info["path"] || ""
    Mix.shell().info("Path: #{adapter_path}")
    Mix.shell().info("")

    # Statistics
    stats = info["stats"] || %{}
    functions = stats["functions"] || 0
    classes = stats["classes"] || 0
    submodules = stats["submodules"] || 0

    Mix.shell().info("Statistics:")
    Mix.shell().info("  Functions: #{functions}")
    Mix.shell().info("  Classes: #{classes}")
    Mix.shell().info("  Submodules: #{submodules}")
    Mix.shell().info("")

    # Files
    files = info["files"] || []
    Mix.shell().info("Files:")

    if Enum.empty?(files) do
      Mix.shell().info("  (none)")
    else
      for file <- files do
        Mix.shell().info("  - #{file}")
      end
    end

    Mix.shell().info("")

    # Quick start
    Mix.shell().info("Quick start:")
    Mix.shell().info("  iex> alias #{elixir_module}")
    Mix.shell().info("  iex> #{elixir_module}.<function>(...)")
    Mix.shell().info("")

    if functions > 0 do
      Mix.shell().info("Discovery:")
      Mix.shell().info("  iex> #{elixir_module}.__functions__()")
      Mix.shell().info("  iex> #{elixir_module}.__search__(\"keyword\")")
      Mix.shell().info("  iex> h #{elixir_module}.<function>")
      Mix.shell().info("")
    end
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
end
