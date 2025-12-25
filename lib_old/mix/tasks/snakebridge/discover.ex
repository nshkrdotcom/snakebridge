defmodule Mix.Tasks.Snakebridge.Discover do
  @moduledoc """
  Discovers a Python library's schema and generates a draft SnakeBridge manifest.

  ## Usage

      mix snakebridge.discover MODULE [OPTIONS]

  ## Arguments

    * `MODULE` - The Python module to discover (e.g., "sympy", "pylatexenc")

  ## Options

    * `--output` - Output path for the manifest file (default: priv/snakebridge/manifests/_drafts/<module>.json)
    * `--depth` - Discovery depth for submodules (default: 2)
    * `--force` - Overwrite existing config file without prompting

  ## Examples

      # Discover SymPy library
      mix snakebridge.discover sympy

      # Custom output path
      mix snakebridge.discover sympy --output priv/snakebridge/manifests/_drafts/sympy.json

      # Deep discovery
      mix snakebridge.discover langchain --depth 3

      # Force overwrite
      mix snakebridge.discover sympy --force
  """

  @shortdoc "Discover a Python library and generate a draft manifest"

  use Mix.Task

  alias SnakeBridge.{Discovery, Manifest, SnakepitLauncher}
  alias SnakeBridge.Manifest.Agent

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} = parse_args(args)

    module_name =
      case positional do
        [name | _] -> name
        [] -> nil
      end

    if module_name == nil do
      Mix.raise(
        "Expected module name as first argument.\n\nUsage: mix snakebridge.discover MODULE"
      )
    end

    depth = Keyword.get(opts, :depth, 2)
    output_path = Keyword.get(opts, :output) || default_output_path(module_name)
    force? = Keyword.get(opts, :force, false)

    Mix.shell().info("Discovering Python library: #{module_name}")
    Mix.shell().info("Discovery depth: #{depth}")

    SnakepitLauncher.ensure_pool_started!()

    # Check if file exists and we're not forcing
    if File.exists?(output_path) and not force? do
      Mix.raise(
        "Config file already exists: #{output_path}\n\n" <>
          "Use --force to overwrite, or specify a different --output path"
      )
    end

    # Discover the library
    case Discovery.discover(module_name, depth: depth) do
      {:ok, schema} ->
        manifest = Agent.suggest_from_schema(schema, module_name)

        write_manifest_file(manifest, output_path)

        Mix.shell().info("✓ Manifest written to: #{output_path}")
        Mix.shell().info("")
        Mix.shell().info("Next steps:")
        Mix.shell().info("  1. Review and customize: #{output_path}")
        Mix.shell().info("  2. Compile manifests: mix snakebridge.manifest.compile")

      {:error, reason} ->
        Mix.raise("Failed to discover module '#{module_name}': #{inspect(reason)}")
    end
  end

  defp parse_args(args) do
    OptionParser.parse(args,
      strict: [
        output: :string,
        depth: :integer,
        force: :boolean
      ],
      aliases: [
        o: :output,
        d: :depth,
        f: :force
      ]
    )
  end

  defp default_output_path(module_name) do
    "priv/snakebridge/manifests/_drafts/#{module_name}.json"
  end

  defp write_manifest_file(manifest, output_path) do
    # Ensure directory exists
    output_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(output_path, Manifest.to_json(manifest))
  end
end
