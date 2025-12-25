defmodule Mix.Tasks.Snakebridge.Adapter.Create do
  @shortdoc "Create a SnakeBridge adapter for a Python library"

  @moduledoc """
  Creates a SnakeBridge adapter for a Python library.

  Uses a two-phase approach:
  1. **Deterministic** (fast, free): Introspects library, generates manifest
  2. **Agent fallback** (if needed): Uses AI to fix issues or handle complex cases

  ## Usage

      mix snakebridge.adapter.create SOURCE [OPTIONS]

  ## Examples

      # From GitHub URL (tries deterministic first)
      mix snakebridge.adapter.create https://github.com/chardet/chardet

      # Force agent-based creation
      mix snakebridge.adapter.create chardet --agent

      # Force specific agent backend
      mix snakebridge.adapter.create chardet --agent --backend claude

      # Limit functions
      mix snakebridge.adapter.create phonenumbers --max-functions 10

  ## Options

    * `--agent` - Skip deterministic, use agent directly
    * `--backend` - Agent backend: `claude` or `codex` (only with --agent)
    * `--max-functions` - Max functions to include (default: 100)
    * `--force` - Re-clone existing library
    * `--status` - Show available backends
  """

  use Mix.Task

  alias SnakeBridge.Adapter.{CodingAgent, Deterministic, Fetcher}

  @switches [
    agent: :boolean,
    backend: :string,
    max_functions: :integer,
    force: :boolean,
    status: :boolean,
    help: :boolean
  ]

  @aliases [
    a: :agent,
    b: :backend,
    n: :max_functions,
    f: :force,
    h: :help
  ]

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:snakebridge)

    {opts, positional, _} = OptionParser.parse(args, strict: @switches, aliases: @aliases)

    cond do
      opts[:help] ->
        Mix.shell().info(@moduledoc)

      opts[:status] ->
        show_status()

      positional == [] ->
        Mix.raise("Usage: mix snakebridge.adapter.create SOURCE [OPTIONS]")

      true ->
        source = List.first(positional)
        create_adapter(source, opts)
    end
  end

  defp show_status do
    backends = CodingAgent.available_backends()
    best = CodingAgent.best_backend()

    Mix.shell().info("\nAvailable Coding Agent Backends:")
    Mix.shell().info("=" |> String.duplicate(40))

    for backend <- [:claude, :codex] do
      available = backend in backends
      indicator = if available, do: "✓", else: "✗"
      Mix.shell().info("  #{indicator} #{backend}")
    end

    Mix.shell().info("\nBest available: #{best || "none"}")

    unless best do
      Mix.shell().info("\nInstall one of:")
      Mix.shell().info("  {:claude_agent_sdk, \"~> 0.6\"}")
      Mix.shell().info("  {:codex_sdk, \"~> 0.4\"}")
    end

    Mix.shell().info("")
  end

  defp create_adapter(source, opts) do
    Mix.shell().info("")
    Mix.shell().info("=" |> String.duplicate(60))
    Mix.shell().info("  SnakeBridge Adapter Creator")
    Mix.shell().info("=" |> String.duplicate(60))
    Mix.shell().info("")

    # Fetch the library
    Mix.shell().info("📦 Fetching: #{source}")

    fetch_opts = [
      force: opts[:force] || false,
      libs_dir: "pythonLibs"
    ]

    case Fetcher.fetch(source, fetch_opts) do
      {:ok, fetch_result} ->
        Mix.shell().info("✓ Cloned to: #{fetch_result.path}")
        Mix.shell().info("")

        if opts[:agent] do
          # User requested agent directly
          run_coding_agent(fetch_result, opts)
        else
          # Try deterministic first, fall back to agent
          run_deterministic_with_fallback(fetch_result, opts)
        end

      {:error, reason} ->
        Mix.raise("Failed to fetch: #{inspect(reason)}")
    end
  end

  defp run_deterministic_with_fallback(fetch_result, opts) do
    Mix.shell().info("Phase 1: Deterministic Creation")
    Mix.shell().info("-" |> String.duplicate(40))

    max_functions = opts[:max_functions] || 100

    create_opts = [
      max_functions: max_functions,
      on_output: &IO.write/1
    ]

    case Deterministic.create(fetch_result.path, fetch_result.name, create_opts) do
      {:ok, result} ->
        # Auto-install the pip package
        install_pip_package(fetch_result.name)

        Mix.shell().info("")
        Mix.shell().info("=" |> String.duplicate(60))
        Mix.shell().info("  ✓ Adapter created successfully!")
        Mix.shell().info("=" |> String.duplicate(60))
        Mix.shell().info("")
        Mix.shell().info("📦 Manifest: #{result.manifest_path}")

        if result.bridge_path do
          Mix.shell().info("🐍 Bridge: #{result.bridge_path}")
        end

        if result.example_path do
          Mix.shell().info("📝 Examples: #{result.example_path}/")
        end

        Mix.shell().info("")
        Mix.shell().info("✨ Ready to use: SnakeBridge.#{Macro.camelize(fetch_result.name)}")
        Mix.shell().info("")
        Mix.shell().info("Run examples:")
        Mix.shell().info("  mix run #{result.example_path}/all_functions.exs")
        Mix.shell().info("")

      {:error, {:introspection_failed, _reason}} ->
        Mix.shell().info("")
        Mix.shell().info("⚠️  Deterministic creation failed, falling back to agent...")
        Mix.shell().info("")
        run_coding_agent(fetch_result, opts)

      {:error, :no_public_functions} ->
        Mix.shell().info("")
        Mix.shell().info("⚠️  No public functions found, falling back to agent...")
        Mix.shell().info("")
        run_coding_agent(fetch_result, opts)

      {:error, {:validation_failed, _errors}} ->
        Mix.shell().info("")
        Mix.shell().info("⚠️  Validation failed, falling back to agent to fix...")
        Mix.shell().info("")
        run_coding_agent(fetch_result, opts)

      {:error, reason} ->
        Mix.shell().info("")
        Mix.shell().info("⚠️  Deterministic creation failed: #{inspect(reason)}")
        Mix.shell().info("    Falling back to agent...")
        Mix.shell().info("")
        run_coding_agent(fetch_result, opts)
    end
  end

  defp run_coding_agent(fetch_result, opts) do
    Mix.shell().info("Phase 2: Agent-Based Creation")
    Mix.shell().info("-" |> String.duplicate(40))

    backend = parse_backend(opts[:backend])
    max_functions = opts[:max_functions] || 100

    # Output callback - stream to console
    on_output = fn text ->
      IO.write(text)
      :ok
    end

    agent_opts = [
      backend: backend,
      on_output: on_output,
      max_functions: max_functions,
      timeout: 300_000
    ]

    case CodingAgent.create_adapter(fetch_result.path, fetch_result.name, agent_opts) do
      {:ok, result} ->
        # Auto-install the pip package
        install_pip_package(fetch_result.name)

        Mix.shell().info("")
        Mix.shell().info("=" |> String.duplicate(60))
        Mix.shell().info("  ✓ Adapter creation complete!")
        Mix.shell().info("=" |> String.duplicate(60))
        Mix.shell().info("")
        Mix.shell().info("✨ Ready to use: SnakeBridge.#{Macro.camelize(fetch_result.name)}")

        if result[:warning] do
          Mix.shell().info("")
          Mix.shell().info("⚠️  #{result[:warning]}")
        end

        Mix.shell().info("")

      {:error, :no_backend_available} ->
        Mix.raise("""
        No coding agent backend available!

        Install one of:
          {:claude_agent_sdk, "~> 0.6"}
          {:codex_sdk, "~> 0.4"}
        """)

      {:error, reason} ->
        Mix.raise("Agent failed: #{inspect(reason)}")
    end
  end

  defp parse_backend(nil), do: nil
  defp parse_backend("claude"), do: :claude
  defp parse_backend("codex"), do: :codex
  defp parse_backend(other), do: Mix.raise("Unknown backend: #{other}")

  defp install_pip_package(lib_name) do
    Mix.shell().info("")
    Mix.shell().info("📥 Installing Python package: #{lib_name}")

    {python, _pip} = SnakeBridge.Python.ensure_environment!(quiet: true)
    SnakeBridge.Python.ensure_package!(python, lib_name, quiet: false)

    Mix.shell().info("  ✓ Package installed")
  end
end
