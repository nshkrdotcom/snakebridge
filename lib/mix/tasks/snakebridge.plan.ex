defmodule Mix.Tasks.Snakebridge.Plan do
  @shortdoc "Preview SnakeBridge generation size"
  @moduledoc """
  Prints a compile-time plan for SnakeBridge code generation without running Python.

  This is most useful for `generate: :all` libraries configured with `module_mode: :docs`,
  where the docs manifest provides an accurate object/module allowlist.
  """

  use Mix.Task

  alias SnakeBridge.Docs.Manifest

  @warn_files 500

  @impl true
  def run(_args) do
    Mix.Task.run("loadconfig")
    config = SnakeBridge.Config.load()

    Enum.each(config.libraries, fn library ->
      Mix.shell().info("")
      Mix.shell().info("Library: #{library.python_name} (generate: #{inspect(library.generate)})")
      Mix.shell().info("  module_mode: #{inspect(library.module_mode || :root)}")

      if library.generate == :all and library.module_mode == :docs do
        print_docs_manifest_plan(library)
      end
    end)
  end

  defp print_docs_manifest_plan(library) do
    case Manifest.load_profile(library) do
      {:ok, profile} ->
        modules = profile.modules
        objects = profile.objects

        class_count = Enum.count(objects, &(&1.kind == :class))
        function_count = Enum.count(objects, &(&1.kind == :function))
        data_count = Enum.count(objects, &(&1.kind == :data))

        total_files = length(modules) + class_count

        Mix.shell().info("  docs_profile: #{library.docs_profile || "full"}")
        Mix.shell().info("  docs_manifest: #{library.docs_manifest}")
        Mix.shell().info("  modules: #{length(modules)}")

        Mix.shell().info(
          "  objects: #{length(objects)} (classes: #{class_count}, functions: #{function_count}, data: #{data_count})"
        )

        Mix.shell().info("  estimated files: ~#{total_files} (module wrappers + class wrappers)")

        if total_files >= @warn_files do
          Mix.shell().info(
            "  [warning] large surface: estimated #{total_files} files; consider using a smaller docs_profile or excluding modules"
          )
        end

      {:error, reason} ->
        Mix.shell().info("  [warning] unable to load docs manifest: #{inspect(reason)}")
    end
  end
end
