defmodule Mix.Tasks.Snakebridge.Docs.Manifest do
  @shortdoc "Generate a docs surface manifest from Sphinx docs"
  @moduledoc """
  Generates a SnakeBridge docs manifest JSON file from Sphinx documentation artifacts.

  Supports:
  - `objects.inv` (Intersphinx inventory) for an inventory of documented objects
  - optional HTML page extraction for:
    - a docs-nav filtered `full` profile (what the docs navigation links to)
    - a curated `summary` profile (fully-qualified object references in page text)

  ## Usage

      mix snakebridge.docs.manifest --library <pkg> --inventory <objects.inv> --out priv/snakebridge/<pkg>.docs.json

      mix snakebridge.docs.manifest --library <pkg> \\
        --inventory <objects.inv> \\
        --nav <api index url or path> \\
        --nav-depth 1 \\
        --summary <api index url or path> \\
        --out priv/snakebridge/<pkg>.docs.json

  You can also pass local paths instead of URLs.

  The output JSON is intended to be committed so builds stay deterministic and
  do not depend on network availability.
  """

  use Mix.Task

  alias SnakeBridge.Docs.{ManifestBuilder, SphinxInventory}

  @impl true
  def run(args) do
    opts = parse_opts!(args)

    inventory = read_inventory!(opts.inventory_source)
    inventory_profile = ManifestBuilder.from_inventory(inventory, opts.library)
    {full_profile, nav_modules} = build_full_profile(inventory, inventory_profile, opts)
    profiles = build_profiles(inventory_profile, full_profile, opts)

    manifest = %{"version" => 1, "library" => opts.library, "profiles" => profiles}

    write_manifest!(opts.out_path, manifest)
    print_summary(opts, profiles, nav_modules)
  end

  defp parse_opts!(args) do
    {opts, _rest, _} =
      OptionParser.parse(args,
        strict: [
          library: :string,
          inventory: :string,
          nav: :string,
          nav_depth: :integer,
          summary: :string,
          out: :string
        ]
      )

    %{
      library: require_opt!(opts, :library),
      inventory_source: require_opt!(opts, :inventory),
      out_path: require_opt!(opts, :out),
      nav_source: Keyword.get(opts, :nav),
      nav_depth: Keyword.get(opts, :nav_depth),
      summary_source: Keyword.get(opts, :summary)
    }
  end

  defp read_inventory!(inventory_source) do
    inventory_content = read_source!(inventory_source)

    case SphinxInventory.parse(inventory_content) do
      {:ok, inventory} -> inventory
      {:error, reason} -> Mix.raise("Failed to parse Sphinx inventory: #{inspect(reason)}")
    end
  end

  defp build_full_profile(_inventory, inventory_profile, %{nav_source: nil}) do
    {inventory_profile, MapSet.new()}
  end

  defp build_full_profile(
         inventory,
         inventory_profile,
         %{library: library, nav_source: nav_source, nav_depth: nav_depth}
       ) do
    nav_modules =
      nav_source
      |> read_source!()
      |> ManifestBuilder.extract_modules_from_html_nav(library)
      |> maybe_filter_nav_modules(library, nav_depth)

    full_profile =
      if Enum.empty?(nav_modules) do
        inventory_profile
      else
        ManifestBuilder.from_inventory(inventory, library, module_allowlist: nav_modules)
      end

    {full_profile, nav_modules}
  end

  defp maybe_filter_nav_modules(modules, library, nav_depth)
       when is_integer(nav_depth) and nav_depth > 0 do
    ManifestBuilder.filter_modules_by_depth(modules, library, nav_depth)
  end

  defp maybe_filter_nav_modules(modules, _library, _nav_depth), do: modules

  defp build_profiles(_inventory_profile, full_profile, %{summary_source: nil}) do
    %{"full" => full_profile}
  end

  defp build_profiles(inventory_profile, full_profile, %{
         library: library,
         summary_source: summary_source
       }) do
    summary_profile =
      summary_source
      |> read_source!()
      |> then(&ManifestBuilder.summary_from_html(inventory_profile, &1, library))

    merged_full_profile = ManifestBuilder.merge_profiles(full_profile, summary_profile)
    %{"summary" => summary_profile, "full" => merged_full_profile}
  end

  defp write_manifest!(out_path, manifest) do
    File.mkdir_p!(Path.dirname(out_path))
    File.write!(out_path, Jason.encode!(manifest, pretty: true))
    Mix.shell().info("Wrote docs manifest: #{out_path}")
  end

  defp print_summary(%{nav_source: nav_source, nav_depth: nav_depth}, profiles, nav_modules) do
    maybe_print_nav_summary(nav_source, nav_modules, nav_depth)

    Enum.each(profiles, fn {profile_name, profile} ->
      Mix.shell().info(
        "  #{profile_name}: #{length(profile["modules"])} modules, #{length(profile["objects"])} objects"
      )
    end)
  end

  defp maybe_print_nav_summary(nil, _nav_modules, _nav_depth), do: :ok

  defp maybe_print_nav_summary(_nav_source, nav_modules, nav_depth) do
    Mix.shell().info("  nav modules extracted: #{Enum.count(nav_modules)}")
    if is_integer(nav_depth) and nav_depth > 0, do: Mix.shell().info("  nav_depth: #{nav_depth}")
    :ok
  end

  defp require_opt!(opts, key) do
    case Keyword.get(opts, key) do
      nil -> Mix.raise("Missing --#{key}")
      value -> value
    end
  end

  defp read_source!(source) when is_binary(source) do
    if String.starts_with?(source, "http://") or String.starts_with?(source, "https://") do
      fetch_url!(source)
    else
      File.read!(source)
    end
  end

  defp fetch_url!(url) do
    :ok = ensure_httpc_started()

    headers = [{~c"user-agent", ~c"Mozilla/5.0 (SnakeBridge docs manifest fetcher)"}]
    request = {to_charlist(url), headers}
    http_opts = [timeout: 30_000, connect_timeout: 10_000]
    opts = [body_format: :binary]

    case :httpc.request(:get, request, http_opts, opts) do
      {:ok, {{_http, 200, _reason}, _headers, body}} ->
        body

      {:ok, {{_http, status, _reason}, _headers, body}} ->
        Mix.raise("HTTP #{status} fetching #{url}: #{inspect(body)}")

      {:error, reason} ->
        Mix.raise("Failed to fetch #{url}: #{inspect(reason)}")
    end
  end

  defp ensure_httpc_started do
    _ = Application.ensure_all_started(:inets)
    _ = Application.ensure_all_started(:ssl)
    :ok
  end
end
