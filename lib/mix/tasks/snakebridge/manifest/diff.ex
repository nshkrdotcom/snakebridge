defmodule Mix.Tasks.Snakebridge.Manifest.Diff do
  @moduledoc """
  Diff a manifest against live Python introspection.

  ## Usage

      mix snakebridge.manifest.diff sympy [--depth N]
      mix snakebridge.manifest.diff priv/snakebridge/manifests/sympy.json [--depth N]
  """

  use Mix.Task

  @shortdoc "Diff manifest against introspected schema"

  @requirements ["app.start"]

  alias SnakeBridge.Manifest
  alias SnakeBridge.Manifest.Diff
  alias SnakeBridge.Manifest.Loader
  alias SnakeBridge.SnakepitLauncher

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [
          depth: :integer
        ],
        aliases: [
          d: :depth
        ]
      )

    target =
      case positional do
        [name | _] -> name
        [] -> nil
      end

    if is_nil(target) do
      Mix.raise("Expected manifest name or path.")
    end

    SnakepitLauncher.ensure_pool_started!()

    depth = Keyword.get(opts, :depth, 1)
    path = resolve_manifest_path(target)

    {:ok, config} = Manifest.from_file(path)
    introspection_module = Manifest.introspection_module(config)
    {:ok, schema} = SnakeBridge.Discovery.discover(introspection_module, depth: depth)

    diff = Diff.diff(config, schema)
    report(path, diff)
  end

  defp resolve_manifest_path(target) do
    cond do
      File.exists?(target) ->
        target

      String.ends_with?(target, ".json") or String.ends_with?(target, ".exs") ->
        Mix.raise("Manifest file not found: #{target}")

      true ->
        name = String.to_atom(target)

        case Loader.manifest_path(name) do
          nil -> Mix.raise("Unknown manifest: #{target}")
          path -> path
        end
    end
  end

  defp report(path, diff) do
    Mix.shell().info("Manifest: #{path}")
    Mix.shell().info("  Manifest functions: #{diff.manifest_count}")
    Mix.shell().info("  Schema functions:   #{diff.schema_count}")

    if diff.missing_in_schema != [] do
      Mix.shell().info("  Missing in schema (manifest-only):")
      Enum.each(diff.missing_in_schema, &Mix.shell().info("    - #{&1}"))
    end

    if diff.new_in_schema != [] do
      Mix.shell().info("  New in schema (not in manifest):")
      Enum.each(diff.new_in_schema, &Mix.shell().info("    - #{&1}"))
    end

    if diff.missing_in_schema == [] and diff.new_in_schema == [] do
      Mix.shell().info("  ✓ Manifest matches schema function list")
    end
  end
end
