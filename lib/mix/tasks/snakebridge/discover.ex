defmodule Mix.Tasks.Snakebridge.Discover do
  @moduledoc """
  Discovers a Python library's schema and generates a SnakeBridge configuration.

  ## Usage

      mix snakebridge.discover MODULE [OPTIONS]

  ## Arguments

    * `MODULE` - The Python module to discover (e.g., "dspy", "langchain")

  ## Options

    * `--output` - Output path for the config file (default: config/snakebridge/<module>.exs)
    * `--depth` - Discovery depth for submodules (default: 2)
    * `--force` - Overwrite existing config file without prompting

  ## Examples

      # Discover DSPy library
      mix snakebridge.discover dspy

      # Custom output path
      mix snakebridge.discover dspy --output lib/configs/dspy.exs

      # Deep discovery
      mix snakebridge.discover langchain --depth 3

      # Force overwrite
      mix snakebridge.discover dspy --force
  """

  @shortdoc "Discover a Python library and generate SnakeBridge config"

  use Mix.Task

  alias SnakeBridge.{Discovery, Config}

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
        # Convert schema to config
        config = Discovery.schema_to_config(schema, python_module: module_name)

        # Validate the config
        case Config.validate(config) do
          {:ok, valid_config} ->
            # Write to file
            write_config_file(valid_config, output_path)
            Mix.shell().info("✓ Config written to: #{output_path}")
            Mix.shell().info("")
            Mix.shell().info("Next steps:")
            Mix.shell().info("  1. Review and customize: #{output_path}")
            Mix.shell().info("  2. Generate modules: mix snakebridge.generate")

          {:error, errors} ->
            Mix.raise("Generated config is invalid:\n" <> Enum.join(errors, "\n"))
        end

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
    "config/snakebridge/#{module_name}.exs"
  end

  defp write_config_file(config, output_path) do
    # Ensure directory exists
    output_path
    |> Path.dirname()
    |> File.mkdir_p!()

    # Generate Elixir code
    config_code = Config.to_elixir_code(config)

    # Write to file
    File.write!(output_path, config_code)
  end
end
