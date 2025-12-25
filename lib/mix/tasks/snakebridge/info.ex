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
    registry = read_registry()
    info = get_library_info!(registry, library)
    display_library_info(library, info)
  end

  defp get_library_info!(registry, library) do
    if Map.has_key?(registry["libraries"], library) do
      registry["libraries"][library]
    else
      show_library_not_found(library, registry["libraries"])
      exit({:shutdown, 1})
    end
  end

  defp show_library_not_found(library, libraries) do
    Mix.shell().error("Library '#{library}' not found.")
    Mix.shell().info("")
    Mix.shell().info("Available libraries:")
    show_available_libraries(libraries)
  end

  defp show_available_libraries(libraries) do
    if map_size(libraries) == 0 do
      Mix.shell().info("  (none)")
      Mix.shell().info("")
      Mix.shell().info("Run `mix snakebridge.gen <library>` to generate an adapter.")
    else
      for lib <- Map.keys(libraries) |> Enum.sort() do
        Mix.shell().info("  - #{lib}")
      end
    end
  end

  defp display_library_info(library, info) do
    print_header(library)
    print_module_info(library, info)
    print_path_info(info)
    print_statistics(info)
    print_files(info)
    print_usage_guide(info)
  end

  defp print_header(library) do
    Mix.shell().info("")
    Mix.shell().info("Library: #{library}")
    Mix.shell().info("=" |> String.duplicate(80))
    Mix.shell().info("")
  end

  defp print_module_info(library, info) do
    python_module = info["python_module"] || library
    python_version = info["python_version"] || "unknown"
    elixir_module = info["elixir_module"] || Macro.camelize(library)

    Mix.shell().info("Python module: #{python_module} (version #{python_version})")
    Mix.shell().info("Elixir module: #{elixir_module}")

    print_generated_timestamp(info["generated_at"])
    Mix.shell().info("")
  end

  defp print_generated_timestamp(nil), do: :ok

  defp print_generated_timestamp(generated_at) do
    formatted_time = String.replace(generated_at, ~r/T(\d{2}:\d{2}:\d{2}).*/, " \\1")
    Mix.shell().info("Generated: #{formatted_time}")
  end

  defp print_path_info(info) do
    adapter_path = info["path"] || ""
    Mix.shell().info("Path: #{adapter_path}")
    Mix.shell().info("")
  end

  defp print_statistics(info) do
    stats = info["stats"] || %{}
    functions = stats["functions"] || 0
    classes = stats["classes"] || 0
    submodules = stats["submodules"] || 0

    Mix.shell().info("Statistics:")
    Mix.shell().info("  Functions: #{functions}")
    Mix.shell().info("  Classes: #{classes}")
    Mix.shell().info("  Submodules: #{submodules}")
    Mix.shell().info("")
  end

  defp print_files(info) do
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
  end

  defp print_usage_guide(info) do
    elixir_module = info["elixir_module"] || Macro.camelize(info["python_module"])
    stats = info["stats"] || %{}
    functions = stats["functions"] || 0

    print_quick_start(elixir_module)
    print_discovery_commands(elixir_module, functions)
  end

  defp print_quick_start(elixir_module) do
    Mix.shell().info("Quick start:")
    Mix.shell().info("  iex> alias #{elixir_module}")
    Mix.shell().info("  iex> #{elixir_module}.<function>(...)")
    Mix.shell().info("")
  end

  defp print_discovery_commands(elixir_module, functions) when functions > 0 do
    Mix.shell().info("Discovery:")
    Mix.shell().info("  iex> #{elixir_module}.__functions__()")
    Mix.shell().info("  iex> #{elixir_module}.__search__(\"keyword\")")
    Mix.shell().info("  iex> h #{elixir_module}.<function>")
    Mix.shell().info("")
  end

  defp print_discovery_commands(_elixir_module, _functions), do: :ok

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
