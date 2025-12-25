defmodule Mix.Tasks.Snakebridge.Manifest.Suggest do
  @moduledoc """
  Suggest a curated manifest via heuristics.

  ## Usage

      mix snakebridge.manifest.suggest MODULE [--output PATH] [--limit N] [--depth N]
  """

  use Mix.Task

  @shortdoc "Suggest a curated manifest (heuristic)"

  @requirements ["app.start"]

  alias SnakeBridge.Manifest
  alias SnakeBridge.Manifest.Agent
  alias SnakeBridge.SnakepitLauncher

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [
          output: :string,
          limit: :integer,
          depth: :integer,
          category: :string,
          prefix: :string,
          elixir_module: :string
        ],
        aliases: [
          o: :output,
          l: :limit,
          d: :depth,
          p: :prefix,
          m: :elixir_module
        ]
      )

    module_name =
      case positional do
        [name | _] -> name
        [] -> nil
      end

    if module_name == nil do
      Mix.raise("Expected module name as first argument.")
    end

    output_path =
      Keyword.get(opts, :output) ||
        "priv/snakebridge/manifests/_drafts/#{module_name}.json"

    limit = Keyword.get(opts, :limit, 20)
    depth = Keyword.get(opts, :depth, 1)

    elixir_module = Keyword.get(opts, :elixir_module)

    SnakepitLauncher.ensure_pool_started!()

    manifest =
      Agent.suggest_manifest(module_name,
        limit: limit,
        depth: depth,
        category: Keyword.get(opts, :category),
        python_path_prefix: Keyword.get(opts, :prefix),
        elixir_module: elixir_module
      )

    output_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(output_path, Manifest.to_json(manifest))

    Mix.shell().info("✓ Suggested manifest written to: #{output_path}")
  end
end
