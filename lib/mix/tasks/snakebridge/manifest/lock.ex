defmodule Mix.Tasks.Snakebridge.Manifest.Lock do
  @moduledoc """
  Generate a manifest lockfile with pinned Python package versions.

  ## Usage

      mix snakebridge.manifest.lock --all
      mix snakebridge.manifest.lock --load sympy,pylatexenc --output priv/snakebridge/manifest.lock.json
      mix snakebridge.manifest.lock priv/snakebridge/manifests/sympy.json --python /path/to/python
  """

  use Mix.Task

  @shortdoc "Generate manifest lockfile (pinned versions)"

  @requirements ["app.start"]

  alias SnakeBridge.Manifest.Loader
  alias SnakeBridge.Manifest.Lockfile

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [
          output: :string,
          load: :string,
          all: :boolean,
          python: :string,
          venv: :string
        ],
        aliases: [
          o: :output,
          p: :python,
          v: :venv
        ]
      )

    manifest_paths = resolve_manifest_paths(opts, positional)

    if manifest_paths == [] do
      Mix.raise("No manifest files resolved for lockfile generation.")
    end

    python_exec = resolve_python_exec(opts)
    output_path = Path.expand(Keyword.get(opts, :output, Lockfile.default_path()))

    case Lockfile.generate(manifest_paths, python_exec) do
      {:ok, lock, warnings} ->
        File.mkdir_p!(Path.dirname(output_path))
        Lockfile.write(lock, output_path)

        Enum.each(warnings, &Mix.shell().error/1)

        Mix.shell().info("✓ Manifest lockfile written to: #{output_path}")

      {:error, {:missing_packages, missing, _results}} ->
        Mix.raise("Missing Python packages: #{Enum.join(missing, ", ")}")

      {:error, :no_manifests} ->
        Mix.raise("No valid manifests found for lockfile generation.")

      {:error, reason} ->
        Mix.raise("Failed to generate lockfile: #{inspect(reason)}")
    end
  end

  defp resolve_manifest_paths(opts, positional) do
    case positional do
      [] ->
        load_setting = load_setting_from_opts(opts)
        custom_paths = Application.get_env(:snakebridge, :custom_manifests, [])
        {files, errors} = Loader.resolve_manifest_files(load_setting, custom_paths)

        if errors != [] do
          Mix.raise("Unknown manifests: #{inspect(errors)}")
        end

        files

      entries ->
        Enum.map(entries, &resolve_manifest_path/1)
    end
  end

  defp resolve_manifest_path(target) do
    cond do
      File.exists?(target) ->
        Path.expand(target)

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

  defp resolve_python_exec(opts) do
    venv_path = Path.expand(Keyword.get(opts, :venv, ".venv"))
    venv_python = Path.join(venv_path, "bin/python3")

    cond do
      python = Keyword.get(opts, :python) ->
        python

      File.exists?(venv_python) ->
        venv_python

      env_python = System.get_env("SNAKEPIT_PYTHON") ->
        env_python

      python = System.find_executable("python3") ->
        python

      true ->
        Mix.raise("Python executable not found. Pass --python or set SNAKEPIT_PYTHON.")
    end
  end
end
