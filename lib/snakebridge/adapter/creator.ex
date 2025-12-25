defmodule SnakeBridge.Adapter.Creator do
  @moduledoc """
  Main orchestrator for creating SnakeBridge adapters.

  Coordinates the full pipeline:
  1. Fetch - Clone/download the Python library
  2. Analyze - Use AI or heuristics to understand the library
  3. Generate - Create manifest, bridge, examples, tests
  4. Validate - Verify the adapter works

  ## Usage

      # From Elixir
      SnakeBridge.Adapter.Creator.create("https://github.com/jazzband/phonenumbers")

      # Via mix task
      mix snakebridge.adapter.create https://github.com/jazzband/phonenumbers
  """

  require Logger

  alias SnakeBridge.Adapter.{
    AgentOrchestrator,
    Fetcher,
    Generator,
    Validator
  }

  @type create_opts :: [
          agent: :claude | :codex | :fallback,
          max_functions: pos_integer(),
          category: String.t(),
          force: boolean(),
          skip_tests: boolean(),
          skip_validate: boolean(),
          skip_example: boolean(),
          venv: String.t(),
          libs_dir: String.t(),
          output_dir: String.t(),
          install_deps: boolean()
        ]

  @type create_result :: %{
          name: String.t(),
          manifest_path: String.t(),
          bridge_path: String.t() | nil,
          example_path: String.t() | nil,
          test_path: String.t() | nil,
          validation: map() | nil,
          analysis: map()
        }

  @doc """
  Creates a complete SnakeBridge adapter from a source.

  ## Parameters

  - `source` - Git URL or PyPI package name
  - `opts` - Options (see @type create_opts)

  ## Returns

  `{:ok, create_result}` or `{:error, reason}`

  ## Examples

      iex> SnakeBridge.Adapter.Creator.create("https://github.com/jazzband/phonenumbers")
      {:ok, %{name: "phonenumbers", manifest_path: "priv/snakebridge/manifests/phonenumbers.json", ...}}

      iex> SnakeBridge.Adapter.Creator.create("chardet", agent: :claude, max_functions: 10)
      {:ok, %{name: "chardet", ...}}
  """
  @spec create(String.t(), create_opts()) :: {:ok, create_result()} | {:error, term()}
  def create(source, opts \\ []) do
    Logger.info("Creating SnakeBridge adapter for: #{source}")

    with {:ok, fetch_result} <- fetch_library(source, opts),
         {:ok, analysis} <- analyze_library(fetch_result, opts),
         {:ok, gen_result} <- generate_adapter(analysis, opts),
         {:ok, validation} <- validate_adapter(gen_result, analysis, opts) do
      result = %{
        name: analysis.name,
        manifest_path: gen_result.manifest_path,
        bridge_path: gen_result.bridge_path,
        example_path: gen_result.example_path,
        test_path: gen_result.test_path,
        validation: validation,
        analysis: analysis
      }

      log_success(result)
      {:ok, result}
    else
      {:error, reason} = error ->
        Logger.error("Adapter creation failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Returns the status of available AI agents.
  """
  @spec agent_status() :: map()
  def agent_status do
    AgentOrchestrator.status()
  end

  # Private - Pipeline stages

  defp fetch_library(source, opts) do
    Logger.info("Stage 1/4: Fetching library...")

    libs_dir = Keyword.get(opts, :libs_dir, "pythonLibs")
    force? = Keyword.get(opts, :force, false)

    case Fetcher.fetch(source, libs_dir: libs_dir, force: force?) do
      {:ok, result} ->
        Logger.info("  ✓ Fetched: #{result.name} → #{result.path}")

        unless result.is_python do
          Logger.warning("  ! Warning: May not be a Python project")
        end

        {:ok, result}

      {:error, reason} ->
        {:error, {:fetch_failed, reason}}
    end
  end

  defp analyze_library(fetch_result, opts) do
    Logger.info("Stage 2/4: Analyzing library...")

    agent = Keyword.get(opts, :agent)
    max_functions = Keyword.get(opts, :max_functions, 20)
    category = Keyword.get(opts, :category)

    agent_name = agent || AgentOrchestrator.best_agent()
    Logger.info("  Using agent: #{agent_name}")

    analysis_opts = [
      agent: agent,
      max_functions: max_functions,
      category: category
    ]

    case AgentOrchestrator.analyze(fetch_result.path, analysis_opts) do
      {:ok, analysis} ->
        # Merge fetch metadata into analysis
        analysis =
          analysis
          |> Map.put(:name, analysis.name || fetch_result.name)
          |> Map.put(:python_module, analysis.python_module || fetch_result.python_module)
          |> Map.put(:pypi_package, analysis.pypi_package || fetch_result.name)

        Logger.info("  ✓ Analyzed: #{length(analysis.functions)} functions selected")

        if analysis.needs_bridge do
          Logger.info("  → Bridge required for serialization")
        end

        {:ok, analysis}

      {:error, reason} ->
        {:error, {:analysis_failed, reason}}
    end
  end

  defp generate_adapter(analysis, opts) do
    Logger.info("Stage 3/4: Generating adapter files...")

    output_dir = Keyword.get(opts, :output_dir, File.cwd!())
    skip_example = Keyword.get(opts, :skip_example, false)
    skip_tests = Keyword.get(opts, :skip_tests, false)

    gen_opts = [
      output_dir: output_dir,
      skip_example: skip_example,
      skip_test: skip_tests
    ]

    case Generator.generate(analysis, gen_opts) do
      {:ok, result} ->
        Logger.info("  ✓ Manifest: #{result.manifest_path}")

        if result.bridge_path do
          Logger.info("  ✓ Bridge: #{result.bridge_path}")
        end

        if result.example_path do
          Logger.info("  ✓ Example: #{result.example_path}")
        end

        if result.test_path do
          Logger.info("  ✓ Test: #{result.test_path}")
        end

        {:ok, result}

      {:error, reason} ->
        {:error, {:generation_failed, reason}}
    end
  end

  defp validate_adapter(gen_result, analysis, opts) do
    skip_validate = Keyword.get(opts, :skip_validate, false)

    if skip_validate do
      Logger.info("Stage 4/4: Validation skipped")
      {:ok, nil}
    else
      Logger.info("Stage 4/4: Validating adapter...")

      venv = Keyword.get(opts, :venv, ".venv")
      install_deps = Keyword.get(opts, :install_deps, true)

      # Install Python package if requested
      if install_deps do
        case Validator.ensure_python_package(
               %{"pypi_package" => analysis.pypi_package, "name" => analysis.name},
               venv
             ) do
          :ok ->
            Logger.info("  ✓ Python package installed")

          {:error, reason} ->
            Logger.warning("  ! Could not install Python package: #{inspect(reason)}")
        end
      end

      validate_opts = [
        bridge_path: gen_result.bridge_path,
        venv: venv,
        skip_live_test: not install_deps
      ]

      {:ok, result} = Validator.validate(gen_result.manifest_path, validate_opts)

      if result.valid do
        Logger.info("  ✓ Validation passed")
      else
        Logger.warning("  ! Validation issues: #{length(result.errors)} errors")

        Enum.each(result.errors, fn err ->
          Logger.warning("    - #{err}")
        end)
      end

      {:ok, result}
    end
  end

  defp log_success(result) do
    Logger.info("")
    Logger.info("═══════════════════════════════════════════════════════")
    Logger.info("  ✓ Adapter created successfully: #{result.name}")
    Logger.info("═══════════════════════════════════════════════════════")
    Logger.info("")
    Logger.info("Next steps:")
    Logger.info("")
    Logger.info("  1. Review the manifest:")
    Logger.info("     #{result.manifest_path}")
    Logger.info("")
    Logger.info("  2. Add to your config:")
    Logger.info("     config :snakebridge, load: [:#{result.name}]")
    Logger.info("")

    if result.example_path do
      Logger.info("  3. Try the example:")
      Logger.info("     mix run #{result.example_path}")
      Logger.info("")
    end

    if result.test_path do
      Logger.info("  4. Run the tests:")
      Logger.info("     mix test #{result.test_path} --only real_python")
      Logger.info("")
    end
  end
end
