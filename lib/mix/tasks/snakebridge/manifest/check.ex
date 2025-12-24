defmodule Mix.Tasks.Snakebridge.Manifest.Check do
  @moduledoc """
  Check manifests against live Python introspection and fail on drift.

  ## Usage

      mix snakebridge.manifest.check --all
      mix snakebridge.manifest.check --load sympy,pylatexenc --depth 2
      mix snakebridge.manifest.check priv/snakebridge/manifests/sympy.json
  """

  use Mix.Task

  @shortdoc "Fail on manifest drift vs introspection"

  @requirements ["app.start"]

  alias SnakeBridge.Manifest
  alias SnakeBridge.Manifest.Diff
  alias SnakeBridge.Manifest.Loader
  alias SnakeBridge.SnakepitLauncher

  @impl Mix.Task
  def run(args) do
    opts = parse_args(args)
    depth = Keyword.get(opts[:parsed], :depth, 1)
    targets = resolve_targets(opts[:parsed], opts[:positional])

    validate_targets(targets)
    SnakepitLauncher.ensure_pool_started!()

    results = check_manifests(targets, depth)
    report(results)
    validate_results(results)
  end

  defp parse_args(args) do
    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [
          depth: :integer,
          load: :string,
          all: :boolean
        ],
        aliases: [
          d: :depth
        ]
      )

    %{parsed: opts, positional: positional}
  end

  defp resolve_targets(opts, positional) do
    case positional do
      [] -> resolve_targets_from_opts(opts)
      entries -> entries
    end
  end

  defp resolve_targets_from_opts(opts) do
    load_setting = load_setting_from_opts(opts)
    custom_paths = Application.get_env(:snakebridge, :custom_manifests, [])
    {files, errors} = Loader.resolve_manifest_files(load_setting, custom_paths)

    if errors != [] do
      Mix.raise("Unknown manifests: #{inspect(errors)}")
    end

    files
  end

  defp validate_targets(targets) do
    if targets == [] do
      Mix.raise("No manifest files resolved for drift check.")
    end
  end

  defp check_manifests(targets, depth) do
    Enum.map(targets, fn target ->
      path = if File.exists?(target), do: target, else: resolve_manifest_path(target)
      {path, check_manifest(path, depth)}
    end)
  end

  defp check_manifest(path, depth) do
    case Manifest.from_file(path) do
      {:ok, config} -> introspect_and_diff(config, depth)
      {:error, reason} -> {:error, reason}
    end
  end

  defp introspect_and_diff(config, depth) do
    introspection_module = Manifest.introspection_module(config)

    case SnakeBridge.Discovery.discover(introspection_module, depth: depth) do
      {:ok, schema} -> Diff.diff(config, schema)
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_results(results) do
    errors = Enum.filter(results, fn {_path, result} -> match?({:error, _}, result) end)
    drift = Enum.filter(results, fn {_path, result} -> drift?(result) end)

    if errors != [] or drift != [] do
      Mix.raise("Manifest drift check failed.")
    else
      Mix.shell().info("✓ All manifests match introspected schema")
    end
  end

  defp load_setting_from_opts(opts) do
    cond do
      Keyword.get(opts, :all, false) ->
        :all

      load = Keyword.get(opts, :load) ->
        load
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.to_atom/1)

      true ->
        Application.get_env(:snakebridge, :load, [])
    end
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

  defp drift?(%{missing_in_schema: missing, new_in_schema: new}) do
    missing != [] or new != []
  end

  defp drift?(_), do: false

  defp report(results) do
    Enum.each(results, fn {path, result} ->
      Mix.shell().info("Manifest: #{path}")
      report_result(result)
    end)
  end

  defp report_result({:error, reason}) do
    Mix.shell().error("  ✗ introspection failed: #{inspect(reason)}")
  end

  defp report_result(diff) do
    Mix.shell().info("  Manifest functions: #{diff.manifest_count}")
    Mix.shell().info("  Schema functions:   #{diff.schema_count}")

    report_missing_functions(diff.missing_in_schema)
    report_new_functions(diff.new_in_schema)
    report_match_status(diff)
  end

  defp report_missing_functions([]), do: :ok

  defp report_missing_functions(missing) do
    Mix.shell().info("  Missing in schema (manifest-only):")
    Enum.each(missing, &Mix.shell().info("    - #{&1}"))
  end

  defp report_new_functions([]), do: :ok

  defp report_new_functions(new) do
    Mix.shell().info("  New in schema (not in manifest):")
    Enum.each(new, &Mix.shell().info("    - #{&1}"))
  end

  defp report_match_status(%{missing_in_schema: [], new_in_schema: []}) do
    Mix.shell().info("  ✓ Manifest matches schema function list")
  end

  defp report_match_status(_), do: :ok
end
