defmodule Mix.Tasks.Snakebridge.Clean do
  @moduledoc """
  Clean SnakeBridge cache and generated files.

  ## Usage

      mix snakebridge.clean [OPTIONS]

  ## Options

    * `--all` - Remove config files in addition to caches

  ## Examples

      # Clean caches only
      mix snakebridge.clean

      # Clean everything including configs
      mix snakebridge.clean --all
  """

  @shortdoc "Clean SnakeBridge caches"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [all: :boolean])
    clean_all? = Keyword.get(opts, :all, false)

    Mix.shell().info("Cleaning SnakeBridge caches...")

    # Clean cache directory
    cache_dir = Application.get_env(:snakebridge, :cache_path, "priv/snakebridge/cache")

    if File.exists?(cache_dir) do
      File.rm_rf!(cache_dir)
      Mix.shell().info("✓ Removed cache directory: #{cache_dir}")
    end

    # Clean in-memory cache if app is running
    if Process.whereis(SnakeBridge.Cache) do
      SnakeBridge.Cache.clear_all()
      Mix.shell().info("✓ Cleared in-memory cache")
    end

    # Optionally clean config files
    if clean_all? do
      if File.exists?("config/snakebridge") do
        File.rm_rf!("config/snakebridge")
        Mix.shell().info("✓ Removed config directory: config/snakebridge")
      end
    end

    Mix.shell().info("")
    Mix.shell().info("Clean complete!")
  end
end
