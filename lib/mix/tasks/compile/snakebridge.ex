defmodule Mix.Tasks.Compile.Snakebridge do
  @moduledoc """
  A Mix compiler that generates Elixir adapters for Python libraries at compile time.

  ## Configuration

  Configure the adapters you need in your `config/config.exs`:

      config :snakebridge,
        adapters: [:json, :numpy, :sympy]

  Or with options:

      config :snakebridge,
        adapters: [
          :json,
          {:numpy, module: MyApp.Numpy},
          {:sympy, functions: ["sqrt", "sin", "cos"]}
        ]

  ## How It Works

  1. This compiler runs before the Elixir compiler
  2. It reads the `:adapters` config
  3. For each adapter, it checks if generated code exists
  4. Missing adapters are generated into `lib/snakebridge_generated/`
  5. A `.gitignore` is created in that directory to keep git clean

  ## Adding to Your Project

  Add `:snakebridge` to your compilers in `mix.exs`:

      def project do
        [
          compilers: [:snakebridge] ++ Mix.compilers(),
          # ...
        ]
      end

  """

  use Mix.Task.Compiler

  alias SnakeBridge.Generator.{Introspector, SourceWriter}

  @generated_dir "lib/snakebridge_generated"
  @manifest_meta_key "__snakebridge__"
  @generator_modules [
    SnakeBridge.Generator.DocFormatter,
    SnakeBridge.Generator.SourceWriter
  ]

  @impl Mix.Task.Compiler
  def run(_args) do
    # Load config first
    Mix.Task.run("loadconfig")

    adapters = Application.get_env(:snakebridge, :adapters, [])
    generator_hash = current_generator_hash()

    if adapters == [] do
      # No adapters configured, nothing to do
      {:ok, []}
    else
      ensure_generated_dir()
      ensure_gitignore()

      results =
        adapters
        |> Enum.map(&normalize_adapter_config/1)
        |> Enum.map(&maybe_generate_adapter(&1, generator_hash))

      errors = Enum.filter(results, &match?({:error, _}, &1))

      if errors == [] do
        {:ok, []}
      else
        {:error, Enum.map(errors, fn {:error, msg} -> diagnostic(msg) end)}
      end
    end
  end

  @impl Mix.Task.Compiler
  def manifests do
    [manifest_path()]
  end

  @impl Mix.Task.Compiler
  def clean do
    File.rm_rf!(@generated_dir)
    File.rm(manifest_path())
    :ok
  end

  # Normalize adapter config into {library, opts} tuple
  defp normalize_adapter_config(adapter) when is_atom(adapter) do
    {Atom.to_string(adapter), []}
  end

  defp normalize_adapter_config({adapter, opts}) when is_atom(adapter) and is_list(opts) do
    {Atom.to_string(adapter), opts}
  end

  defp normalize_adapter_config(adapter) when is_binary(adapter) do
    {adapter, []}
  end

  # Check if adapter needs generation and generate if so
  defp maybe_generate_adapter({library, opts}, generator_hash) do
    output_dir = adapter_output_dir(library)

    if needs_generation?(library, output_dir, generator_hash) do
      generate_adapter(library, output_dir, opts, generator_hash)
    else
      :ok
    end
  end

  defp needs_generation?(library, output_dir, generator_hash) do
    manifest = read_manifest()
    stored_entry = Map.get(manifest, library)
    stored_hash = (stored_entry || %{})["generator_hash"]

    cond do
      # Directory doesn't exist
      not File.dir?(output_dir) ->
        true

      # Not in manifest
      is_nil(stored_entry) ->
        true

      # Generator changed (docs/types/source formatting)
      stored_hash != generator_hash ->
        true

      # Version mismatch (future: check Python lib version)
      true ->
        false
    end
  end

  defp generate_adapter(library, output_dir, opts, generator_hash) do
    Mix.shell().info("SnakeBridge: Generating #{library} adapter...")

    case Introspector.introspect(library) do
      {:ok, introspection} ->
        # Merge opts with defaults
        gen_opts =
          Keyword.merge(
            [use_snakebridge: true, add_python_annotations: true],
            opts
          )

        case SourceWriter.generate_files(introspection, output_dir, gen_opts) do
          {:ok, files, stats} ->
            Mix.shell().info(
              "  Generated #{stats[:functions] || 0} functions, #{stats[:classes] || 0} classes"
            )

            # Update manifest
            update_manifest(
              library,
              %{
                generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
                files: files,
                stats: stats
              },
              generator_hash
            )

            :ok

          {:error, reason} ->
            {:error, "Failed to generate #{library}: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to introspect #{library}: #{reason}"}
    end
  end

  defp adapter_output_dir(library) do
    Path.join(@generated_dir, library)
  end

  defp ensure_generated_dir do
    File.mkdir_p!(@generated_dir)
  end

  defp ensure_gitignore do
    gitignore_path = Path.join(@generated_dir, ".gitignore")

    unless File.exists?(gitignore_path) do
      # Ignore everything except the gitignore itself
      File.write!(gitignore_path, """
      # Auto-generated by SnakeBridge compiler
      # This directory contains generated Python adapters
      # Do not edit - regenerate with: mix compile
      *
      !.gitignore
      """)
    end
  end

  # Manifest management for tracking what's been generated
  defp manifest_path do
    Path.join([Mix.Project.manifest_path(), "snakebridge.manifest"])
  end

  defp read_manifest do
    case File.read(manifest_path()) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> data
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  defp update_manifest(library, data, generator_hash) do
    manifest = read_manifest()
    data = Map.put(data, "generator_hash", generator_hash)

    updated =
      manifest
      |> put_manifest_meta(generator_hash)
      |> Map.put(library, data)

    File.mkdir_p!(Path.dirname(manifest_path()))
    File.write!(manifest_path(), Jason.encode!(updated, pretty: true))
  end

  defp manifest_meta(manifest) do
    Map.get(manifest, @manifest_meta_key, %{})
  end

  defp put_manifest_meta(manifest, generator_hash) do
    meta =
      manifest
      |> manifest_meta()
      |> Map.put("generator_hash", generator_hash)

    Map.put(manifest, @manifest_meta_key, meta)
  end

  defp current_generator_hash do
    data =
      @generator_modules
      |> Enum.map(&module_md5/1)
      |> :erlang.term_to_binary()

    :crypto.hash(:sha256, data)
    |> Base.encode16(case: :lower)
  end

  defp module_md5(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} -> module.module_info(:md5)
      _ -> :unknown
    end
  end

  defp diagnostic(message) do
    %Mix.Task.Compiler.Diagnostic{
      compiler_name: "snakebridge",
      details: nil,
      file: "config/config.exs",
      message: message,
      position: 1,
      severity: :error
    }
  end
end
