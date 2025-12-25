defmodule Mix.Tasks.Snakebridge.Gen do
  use Mix.Task

  @shortdoc "Generate Elixir adapter for a Python library"

  @moduledoc """
  Generate an Elixir adapter module for a Python library.

  This task introspects a Python library and generates modular, fully-typed Elixir
  adapters with functions, specs, and documentation, organized into logical file
  structures.

  ## Usage

      mix snakebridge.gen <library> [options]

  ## Examples

      # Generate adapter for the json library
      mix snakebridge.gen json

      # Generate with custom module name
      mix snakebridge.gen json --module MyApp.JsonAdapter

      # Generate to specific output directory
      mix snakebridge.gen numpy --output lib/my_adapters/

      # Force overwrite existing library
      mix snakebridge.gen requests --force

      # Limit to specific functions
      mix snakebridge.gen json --functions dumps,loads

      # Exclude specific functions
      mix snakebridge.gen os --exclude system,exec

  ## Options

    * `--output` - Output directory path (default: lib/snakebridge/adapters/<library>/)
    * `--module` - Custom module name (default: <Library>)
    * `--force` - Remove existing library and regenerate
    * `--functions` - Comma-separated list of functions to include
    * `--exclude` - Comma-separated list of functions to exclude

  ## How It Works

  1. Runs Python introspection script on the library
  2. Parses function signatures, types, and docstrings
  3. Maps Python types to Elixir specs
  4. Generates modular Elixir source files
  5. Writes to output directory
  6. Registers library in the registry

  ## Requirements

  - Python 3.7+ in PATH
  - Target Python library must be importable
  """

  alias SnakeBridge.Generator.{Introspector, SourceWriter}

  @impl Mix.Task
  def run([]) do
    Mix.shell().error("Error: Library name required")
    Mix.shell().info("")
    Mix.shell().info("Usage: mix snakebridge.gen <library> [options]")
    Mix.shell().info("")
    Mix.shell().info("Examples:")
    Mix.shell().info("  mix snakebridge.gen json")
    Mix.shell().info("  mix snakebridge.gen numpy --output lib/adapters/numpy.ex")
    Mix.shell().info("")
    exit({:shutdown, 1})
  end

  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          output: :string,
          module: :string,
          force: :boolean,
          functions: :string,
          exclude: :string
        ]
      )

    if invalid != [] do
      Mix.shell().error("Invalid options: #{inspect(invalid)}")
      exit({:shutdown, 1})
    end

    case rest do
      [library] ->
        generate_adapter(library, opts)

      [] ->
        Mix.shell().error("Error: Library name required")
        exit({:shutdown, 1})

      _ ->
        Mix.shell().error("Error: Only one library name allowed")
        exit({:shutdown, 1})
    end
  end

  defp generate_adapter(library, opts) do
    output_dir = opts[:output] || default_output_dir(library)

    # Handle --force flag: remove existing library first
    if opts[:force] && library_exists?(library, output_dir) do
      remove_existing_library(library, output_dir)
    end

    # Check if directory exists (and is not empty)
    if directory_exists_and_not_empty?(output_dir) && !opts[:force] do
      unless confirm_overwrite(output_dir) do
        Mix.shell().info("Cancelled.")
        exit({:shutdown, 0})
      end
    end

    Mix.shell().info("Introspecting Python library: #{library}...")

    case Introspector.introspect(library) do
      {:ok, introspection} ->
        introspection = filter_functions(introspection, opts)

        # Show introspection summary
        show_introspection_summary(introspection)

        Mix.shell().info("")
        Mix.shell().info("Generating Elixir adapters...")

        # Generate files using SourceWriter
        result = SourceWriter.generate_files(introspection, output_dir, opts)

        case result do
          {:ok, files, stats} ->
            Mix.shell().info("")
            show_success(library, output_dir, files, stats, introspection)

            # Register the library
            register_library(library, output_dir, files, stats, introspection)

          {:error, reason} ->
            Mix.shell().error("Failed to generate files: #{reason}")
            exit({:shutdown, 1})
        end

      {:error, reason} ->
        Mix.shell().error("Failed to introspect library: #{reason}")
        Mix.shell().info("")
        Mix.shell().info("Troubleshooting:")
        Mix.shell().info("  - Ensure Python 3.7+ is in PATH")
        Mix.shell().info("  - Verify the library is installed: pip install #{library}")
        Mix.shell().info("  - Try importing in Python: python -c 'import #{library}'")
        exit({:shutdown, 1})
    end
  end

  defp default_output_dir(library) do
    Path.join(["lib", "snakebridge", "adapters", library])
  end

  defp library_exists?(library, output_dir) do
    File.dir?(output_dir) || registry_has_library?(library)
  end

  defp directory_exists_and_not_empty?(dir) do
    File.dir?(dir) && File.ls!(dir) != []
  end

  defp registry_has_library?(library) do
    # Try to check registry, but don't fail if it doesn't exist
    try do
      if Code.ensure_loaded?(SnakeBridge.Registry) do
        SnakeBridge.Registry.generated?(library)
      else
        false
      end
    rescue
      _ -> false
    end
  end

  defp remove_existing_library(library, output_dir) do
    Mix.shell().info("Removing existing #{library} adapter...")

    # Unregister from registry if it exists
    try do
      if Code.ensure_loaded?(SnakeBridge.Registry) do
        SnakeBridge.Registry.unregister(library)
      end
    rescue
      _ -> :ok
    end

    # Remove directory
    if File.dir?(output_dir) do
      File.rm_rf!(output_dir)
      Mix.shell().info("  Deleted: #{output_dir}")
    end

    Mix.shell().info("")
  end

  defp confirm_overwrite(path) do
    Mix.shell().yes?("Directory #{path} already exists. Overwrite?")
  end

  defp filter_functions(introspection, opts) do
    functions = introspection["functions"] || []

    functions =
      if include_list = opts[:functions] do
        included = String.split(include_list, ",", trim: true)
        Enum.filter(functions, &(&1["name"] in included))
      else
        functions
      end

    functions =
      if exclude_list = opts[:exclude] do
        excluded = String.split(exclude_list, ",", trim: true)
        Enum.reject(functions, &(&1["name"] in excluded))
      else
        functions
      end

    Map.put(introspection, "functions", functions)
  end

  defp show_introspection_summary(introspection) do
    function_count = length(introspection["functions"] || [])
    class_count = length(introspection["classes"] || [])

    # Count namespaces (submodules)
    namespaces = count_namespaces(introspection)

    # Count methods in classes
    method_count =
      (introspection["classes"] || [])
      |> Enum.map(fn class -> length(class["methods"] || []) end)
      |> Enum.sum()

    Mix.shell().info("  Found #{function_count} functions in #{namespaces} namespaces")

    if class_count > 0 do
      Mix.shell().info("  Found #{class_count} classes with #{method_count} methods")
    end
  end

  defp count_namespaces(introspection) do
    # Count unique module namespaces from functions and classes
    function_namespaces =
      (introspection["functions"] || [])
      |> Enum.map(fn func -> func["module"] || introspection["module"] end)
      |> Enum.uniq()

    class_namespaces =
      (introspection["classes"] || [])
      |> Enum.map(fn class -> class["module"] || introspection["module"] end)
      |> Enum.uniq()

    (function_namespaces ++ class_namespaces)
    |> Enum.uniq()
    |> length()
    |> max(1)
  end

  defp show_success(library, output_dir, _files, stats, introspection) do
    module_name = get_module_name(introspection)

    Mix.shell().info("Success! Generated #{library} adapter:")
    Mix.shell().info("  Path: #{output_dir}/")
    Mix.shell().info("  Module: #{module_name}")
    Mix.shell().info("  Functions: #{stats[:functions] || 0}")

    if stats[:classes] && stats[:classes] > 0 do
      Mix.shell().info("  Classes: #{stats[:classes]}")
    end

    if stats[:submodules] && length(stats[:submodules]) > 0 do
      submodule_names = Enum.join(stats[:submodules], ", ")
      Mix.shell().info("  Submodules: #{submodule_names}")
    end

    Mix.shell().info("")
    Mix.shell().info("Quick start:")
    Mix.shell().info("  iex> alias #{module_name}")

    # Show example function call
    if stats[:functions] && stats[:functions] > 0 do
      first_fn = List.first(introspection["functions"] || [])

      if first_fn do
        fn_name = first_fn["name"]
        param_count = length(first_fn["parameters"] || [])
        args = if param_count > 0, do: "(...)", else: "()"
        Mix.shell().info("  iex> #{module_name}.#{fn_name}#{args}")
      end
    end

    Mix.shell().info("")
    Mix.shell().info("Discovery:")
    Mix.shell().info("  iex> #{module_name}.__functions__()")
    Mix.shell().info("  iex> h #{module_name}")
    Mix.shell().info("")
  end

  defp get_module_name(introspection) do
    python_module = introspection["module"] || "Unknown"

    python_module
    |> String.split(".")
    |> Enum.map(&Macro.camelize/1)
    |> Enum.join(".")
  end

  defp register_library(library, output_dir, files, stats, introspection) do
    # Only register if Registry module is available
    try do
      if Code.ensure_loaded?(SnakeBridge.Registry) do
        python_module = introspection["module"] || library
        elixir_module = get_module_name(introspection)
        version = introspection["version"] || "unknown"

        # Ensure stats has required fields
        normalized_stats = %{
          functions: stats[:functions] || 0,
          classes: stats[:classes] || 0,
          submodules: length(stats[:submodules] || [])
        }

        registry_data = %{
          python_module: python_module,
          python_version: version,
          elixir_module: elixir_module,
          generated_at: DateTime.utc_now(),
          path: output_dir,
          files: files,
          stats: normalized_stats
        }

        case SnakeBridge.Registry.register(library, registry_data) do
          :ok ->
            :ok

          {:error, reason} ->
            Mix.shell().info("Warning: Failed to register library: #{inspect(reason)}")
        end
      end
    rescue
      error ->
        Mix.shell().info("Warning: Registry not available: #{inspect(error)}")
    end
  end
end
