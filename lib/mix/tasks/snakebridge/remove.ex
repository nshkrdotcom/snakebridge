defmodule Mix.Tasks.Snakebridge.Remove do
  use Mix.Task

  @shortdoc "Remove a generated adapter"

  @moduledoc """
  Removes a generated Python library adapter.

  This task removes the generated adapter directory and updates the registry.

  ## Usage

      mix snakebridge.remove <library>

  ## Examples

      # Remove the numpy adapter
      mix snakebridge.remove numpy

      # Remove the json adapter
      mix snakebridge.remove json

  ## What it does

  1. Reads the registry to find the adapter location
  2. Deletes the adapter directory
  3. Updates the registry to remove the library entry
  4. Shows what was removed

  ## Requirements

  - Registry file must exist at `priv/snakebridge/registry.json`
  - Library must be in the registry
  """

  @registry_path "priv/snakebridge/registry.json"

  @impl Mix.Task
  def run([]) do
    raise Mix.Error, "Library name required\n\nUsage: mix snakebridge.remove <library>"
  end

  def run([library | _rest]) do
    # Read registry
    registry = read_registry()

    # Check if library exists in registry
    unless Map.has_key?(registry["libraries"], library) do
      Mix.shell().error("Library '#{library}' not found in registry.")
      Mix.shell().info("")
      Mix.shell().info("Available libraries:")

      if map_size(registry["libraries"]) == 0 do
        Mix.shell().info("  (none)")
      else
        for lib <- Map.keys(registry["libraries"]) |> Enum.sort() do
          Mix.shell().info("  - #{lib}")
        end
      end

      exit({:shutdown, 1})
    end

    Mix.shell().info("Removing #{library}...")

    # Get library info
    lib_info = registry["libraries"][library]
    adapter_path = lib_info["path"]

    # Remove adapter directory
    if File.dir?(adapter_path) do
      File.rm_rf!(adapter_path)
      Mix.shell().info("  Deleted: #{adapter_path}")
    else
      Mix.shell().info("  Warning: Adapter directory does not exist: #{adapter_path}")
    end

    # Update registry
    updated_libraries = Map.delete(registry["libraries"], library)
    updated_registry = Map.put(registry, "libraries", updated_libraries)
    write_registry(updated_registry)
    Mix.shell().info("  Updated: #{@registry_path}")

    Mix.shell().info("")
    Mix.shell().info("Done. Run `mix snakebridge.gen #{library}` to regenerate.")
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
    # Update generated_at timestamp
    registry = Map.put(registry, "generated_at", DateTime.utc_now() |> DateTime.to_iso8601())

    # Ensure directory exists
    File.mkdir_p!(Path.dirname(@registry_path))

    # Write registry
    @registry_path
    |> File.write!(Jason.encode!(registry, pretty: true))
  end
end
