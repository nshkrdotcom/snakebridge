defmodule Mix.Tasks.Snakebridge.Manifest.Validate do
  @moduledoc """
  Validate SnakeBridge manifest files.

  ## Usage

      mix snakebridge.manifest.validate [PATHS...]

  If no paths are provided, validates all built-in manifests.
  """

  use Mix.Task

  @shortdoc "Validate SnakeBridge manifest files"

  @impl Mix.Task
  def run(args) do
    files = resolve_files(args)

    if Enum.empty?(files) do
      Mix.shell().info("No manifest files found.")
      return()
    end

    results = Enum.map(files, &validate_file/1)

    errors =
      results
      |> Enum.filter(&match?({:error, _}, &1))
      |> Enum.map(fn {:error, reason} -> reason end)

    if errors == [] do
      Mix.shell().info("✓ All manifests valid (#{length(files)}).")
    else
      Mix.raise("Manifest validation failed:\n" <> Enum.join(List.flatten(errors), "\n"))
    end
  end

  defp resolve_files([]) do
    Path.wildcard("priv/snakebridge/manifests/*.{json,exs}")
    |> Enum.reject(&(String.ends_with?(&1, "_index.json") or String.ends_with?(&1, "_index.exs")))
  end

  defp resolve_files(paths) do
    paths
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.filter(&(String.ends_with?(&1, ".json") or String.ends_with?(&1, ".exs")))
    |> Enum.reject(&(String.ends_with?(&1, "_index.json") or String.ends_with?(&1, "_index.exs")))
  end

  defp validate_file(path) do
    case SnakeBridge.Manifest.validate_file(path) do
      {:ok, _} ->
        Mix.shell().info("✓ #{path}")
        {:ok, path}

      {:error, errors} ->
        {:error, Enum.map(errors, fn err -> "#{path}: #{err}" end)}
    end
  end

  defp return, do: nil
end
