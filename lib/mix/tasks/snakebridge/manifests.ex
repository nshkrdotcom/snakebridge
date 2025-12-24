defmodule Mix.Tasks.Snakebridge.Manifests do
  @moduledoc """
  List built-in SnakeBridge manifests.

  ## Usage

      mix snakebridge.manifests
  """

  use Mix.Task

  alias SnakeBridge.Manifest.Loader

  @shortdoc "List built-in SnakeBridge manifests"

  @impl Mix.Task
  def run(_args) do
    index = Loader.index()

    if map_size(index) == 0 do
      Mix.shell().info("No built-in manifests found.")
      return()
    end

    Mix.shell().info("Built-in manifests:")

    index
    |> Enum.sort_by(fn {name, _} -> to_string(name) end)
    |> Enum.each(fn {name, entry} ->
      file = Map.get(entry, :file) || Map.get(entry, "file")
      python_module = Map.get(entry, :python_module) || Map.get(entry, "python_module")
      version = Map.get(entry, :version) || Map.get(entry, "version")
      status = Map.get(entry, :status) || Map.get(entry, "status")
      description = Map.get(entry, :description) || Map.get(entry, "description")

      Mix.shell().info("  - #{name} (#{python_module}) #{version} [#{status}] - #{description}")
      Mix.shell().info("    #{file}")
    end)
  end

  defp return, do: nil
end
