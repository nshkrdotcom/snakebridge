defmodule Mix.Tasks.Snakebridge.Manifest.Clean do
  @moduledoc """
  Remove generated manifest modules and recompile them.

  ## Usage

      mix snakebridge.manifest.clean
      mix snakebridge.manifest.clean --output lib/snakebridge/generated --all
      mix snakebridge.manifest.clean --load sympy,pylatexenc
  """

  use Mix.Task

  @shortdoc "Clean and recompile manifest-generated modules"

  @requirements ["app.start"]

  alias SnakeBridge.Manifest.Compiler
  alias SnakeBridge.Manifest.Loader

  @impl Mix.Task
  def run(args) do
    {opts, _positional, _} =
      OptionParser.parse(args,
        strict: [
          output: :string,
          load: :string,
          all: :boolean
        ],
        aliases: [
          o: :output
        ]
      )

    output_dir = Path.expand(Keyword.get(opts, :output, "lib/snakebridge/generated"))

    if File.dir?(output_dir) do
      File.rm_rf!(output_dir)
    end

    load_setting = load_setting_from_opts(opts)
    custom_paths = Application.get_env(:snakebridge, :custom_manifests, [])
    {files, errors} = Loader.resolve_manifest_files(load_setting, custom_paths)

    if errors != [] do
      Mix.shell().error("Unknown manifests: #{inspect(errors)}")
    end

    if files == [] do
      Mix.raise("No manifest files resolved for compilation.")
    end

    {:ok, outputs} = Compiler.compile_files(files, output_dir)

    Mix.shell().info("Cleaned and compiled #{length(outputs)} modules into #{output_dir}")
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
end
