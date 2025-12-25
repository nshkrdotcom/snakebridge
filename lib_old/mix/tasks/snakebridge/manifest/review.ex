defmodule Mix.Tasks.Snakebridge.Manifest.Review do
  @moduledoc """
  Interactively review a manifest's function list.

  ## Usage

      mix snakebridge.manifest.review sympy
      mix snakebridge.manifest.review priv/snakebridge/manifests/sympy.json --output priv/snakebridge/manifests/sympy.reviewed.json
      mix snakebridge.manifest.review sympy --schema priv/snakebridge/schemas/sympy.json
      mix snakebridge.manifest.review sympy --introspect --depth 2
  """

  use Mix.Task

  @shortdoc "Interactively review manifest functions"

  @requirements ["app.start"]

  alias SnakeBridge.Manifest
  alias SnakeBridge.Manifest.Loader
  alias SnakeBridge.Manifest.Reader
  alias SnakeBridge.SnakepitLauncher

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [
          output: :string,
          schema: :string,
          introspect: :boolean,
          depth: :integer
        ],
        aliases: [
          o: :output,
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

    path = resolve_manifest_path(target)
    manifest = load_manifest_map!(path)
    functions_key = if Map.has_key?(manifest, "functions"), do: "functions", else: :functions
    functions = Map.get(manifest, functions_key) || []

    if functions == [] do
      Mix.shell().info("No functions found in manifest: #{path}")
      return()
    end

    schema =
      load_schema(opts, manifest)

    schema_functions = Map.get(schema || %{}, "functions", %{})

    reviewed = review_functions(functions, schema_functions)

    updated = Map.put(manifest, functions_key, reviewed)
    output_path = Keyword.get(opts, :output, path)

    File.write!(output_path, Manifest.to_json(updated))
    Mix.shell().info("✓ Reviewed manifest written to: #{output_path}")
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

  defp load_manifest_map!(path) do
    manifest = Reader.read_file!(path)

    case manifest do
      %SnakeBridge.Config{} ->
        Mix.raise("Manifest must be a map (not a %SnakeBridge.Config{}): #{path}")

      %{} ->
        manifest
    end
  end

  defp load_schema(opts, manifest) do
    schema_path = Keyword.get(opts, :schema)
    introspect? = Keyword.get(opts, :introspect, false)
    depth = Keyword.get(opts, :depth, 1)
    python_module = Map.get(manifest, :python_module) || Map.get(manifest, "python_module")

    cond do
      schema_path ->
        schema_path
        |> File.read!()
        |> Jason.decode!()

      introspect? and is_binary(python_module) ->
        SnakepitLauncher.ensure_pool_started!()
        {:ok, schema} = SnakeBridge.Discovery.discover(python_module, depth: depth)
        schema

      true ->
        nil
    end
  rescue
    e ->
      Mix.raise("Failed to load schema: #{Exception.message(e)}")
  end

  defp review_functions(functions, schema_functions) do
    total = length(functions)

    {kept, _} =
      Enum.reduce_while(Enum.with_index(functions, 1), {[], :cont}, fn {entry, idx}, {acc, _} ->
        name = function_name_from_entry(entry)

        schema_func =
          if is_nil(name) do
            nil
          else
            Map.get(schema_functions, name) || Map.get(schema_functions, to_string(name))
          end

        Mix.shell().info("\n#{idx}/#{total} #{name}")
        print_details(entry, schema_func)

        case prompt_action() do
          :keep ->
            {:cont, {[entry | acc], :cont}}

          :drop ->
            {:cont, {acc, :cont}}

          :keep_all ->
            remaining = functions_remaining(functions, idx)
            {:halt, {Enum.reverse(remaining) ++ [entry | acc], :halt}}

          :quit ->
            {:halt, {acc, :halt}}
        end
      end)

    Enum.reverse(kept)
  end

  defp functions_remaining(functions, idx) do
    functions
    |> Enum.drop(idx)
  end

  defp prompt_action do
    prompt = "Keep? [Y]es/[n]o/[a]ll/[q]uit: "

    case IO.gets(prompt) do
      :eof ->
        :keep

      {:error, _} ->
        :keep

      input when is_binary(input) ->
        input
        |> String.trim()
        |> String.downcase()
        |> parse_action()
    end
  end

  defp parse_action(""), do: :keep
  defp parse_action("y"), do: :keep
  defp parse_action("yes"), do: :keep
  defp parse_action("n"), do: :drop
  defp parse_action("no"), do: :drop
  defp parse_action("a"), do: :keep_all
  defp parse_action("all"), do: :keep_all
  defp parse_action("q"), do: :quit
  defp parse_action("quit"), do: :quit
  defp parse_action(_), do: :keep

  defp print_details(entry, schema_func) do
    doc = entry_doc(entry, schema_func)
    args = entry_args(entry, schema_func)
    returns = entry_returns(entry, schema_func)

    if doc != "" do
      Mix.shell().info("  doc: #{doc}")
    end

    if args != [] do
      Mix.shell().info("  args: #{Enum.join(args, ", ")}")
    end

    if returns != nil and returns != "" do
      Mix.shell().info("  returns: #{inspect(returns)}")
    end
  end

  defp entry_doc(entry, schema_func) do
    extract_entry_doc(entry) || schema_doc(schema_func) || ""
  end

  defp extract_entry_doc({_, opts}) when is_list(opts) do
    Keyword.get(opts, :doc) || Keyword.get(opts, :docstring)
  end

  defp extract_entry_doc({_, opts}) when is_map(opts) do
    extract_doc_from_map(opts)
  end

  defp extract_entry_doc(%{} = opts) do
    extract_doc_from_map(opts)
  end

  defp extract_entry_doc(_), do: nil

  defp extract_doc_from_map(opts) do
    Map.get(opts, :doc) || Map.get(opts, "doc") ||
      Map.get(opts, :docstring) || Map.get(opts, "docstring")
  end

  defp schema_doc(nil), do: nil

  defp schema_doc(schema_func) do
    Map.get(schema_func, "docstring") || Map.get(schema_func, :docstring)
  end

  defp entry_args(entry, schema_func) do
    args =
      case entry do
        {_, opts} when is_list(opts) -> Keyword.get(opts, :args)
        {_, opts} when is_map(opts) -> Map.get(opts, :args) || Map.get(opts, "args")
        %{} = opts -> Map.get(opts, :args) || Map.get(opts, "args")
        _ -> nil
      end

    args || schema_args(schema_func) || []
  end

  defp schema_args(nil), do: nil

  defp schema_args(schema_func) do
    params = Map.get(schema_func, "parameters") || Map.get(schema_func, :parameters) || []

    params
    |> Enum.map(fn param -> Map.get(param, "name") || Map.get(param, :name) end)
    |> Enum.reject(&is_nil/1)
  end

  defp entry_returns(entry, schema_func) do
    extract_entry_returns(entry) || schema_return(schema_func)
  end

  defp extract_entry_returns({_, opts}) when is_list(opts) do
    Keyword.get(opts, :returns) || Keyword.get(opts, :return)
  end

  defp extract_entry_returns({_, opts}) when is_map(opts) do
    extract_returns_from_map(opts)
  end

  defp extract_entry_returns(%{} = opts) do
    extract_returns_from_map(opts)
  end

  defp extract_entry_returns(_), do: nil

  defp extract_returns_from_map(opts) do
    Map.get(opts, :returns) || Map.get(opts, "returns") ||
      Map.get(opts, :return) || Map.get(opts, "return")
  end

  defp schema_return(nil), do: nil

  defp schema_return(schema_func) do
    Map.get(schema_func, "return_type") || Map.get(schema_func, :return_type)
  end

  defp function_name_from_entry({name, _opts}) when is_atom(name), do: Atom.to_string(name)
  defp function_name_from_entry({name, _opts}) when is_binary(name), do: name

  defp function_name_from_entry(%{} = opts) do
    cond do
      Map.has_key?(opts, :python_name) -> Map.get(opts, :python_name)
      Map.has_key?(opts, "python_name") -> Map.get(opts, "python_name")
      Map.has_key?(opts, :name) -> normalize_name(Map.get(opts, :name))
      Map.has_key?(opts, "name") -> normalize_name(Map.get(opts, "name"))
      Map.has_key?(opts, :python_path) -> last_segment(Map.get(opts, :python_path))
      Map.has_key?(opts, "python_path") -> last_segment(Map.get(opts, "python_path"))
      true -> nil
    end
  end

  defp normalize_name(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize_name(name) when is_binary(name), do: name
  defp normalize_name(_), do: nil

  defp last_segment(nil), do: nil

  defp last_segment(path) when is_binary(path) do
    path |> String.split(".") |> List.last()
  end

  defp return, do: nil
end
