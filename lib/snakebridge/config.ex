defmodule SnakeBridge.Config do
  @moduledoc """
  Compile-time configuration for SnakeBridge.
  """

  defstruct [
    :libraries,
    :auto_install,
    :generated_dir,
    :generated_layout,
    :metadata_dir,
    :helper_paths,
    :helper_pack_enabled,
    :helper_allowlist,
    :inline_enabled,
    :strict,
    :verbose,
    :scan_paths,
    :scan_exclude,
    :introspector,
    :docs,
    :runtime_client,
    :ledger,
    :signature_sources,
    :strict_signatures,
    :min_signature_tier,
    :stub_search_paths,
    :use_typeshed,
    :typeshed_path,
    :stubgen,
    :coverage_report
  ]

  defmodule Library do
    @moduledoc """
    Configuration struct for a single Python library binding.

    ## Options

    - `:generate` - Controls which symbols are generated:
      - `:used` (default) - Only generate wrappers for symbols detected in your code
      - `:all` - Generate wrappers for ALL public symbols in the Python module
    - `:docs_url` - Explicit documentation URL for third-party libraries
    """

    defstruct [
      :name,
      :version,
      :module_name,
      :python_name,
      :pypi_package,
      :docs_url,
      :extras,
      include: [],
      exclude: [],
      streaming: [],
      submodules: false,
      generate: :used,
      signature_sources: nil,
      strict_signatures: nil,
      min_signature_tier: nil,
      stub_search_paths: nil,
      use_typeshed: nil,
      typeshed_path: nil,
      stubgen: nil
    ]

    @type generate_mode :: :all | :used

    @type t :: %__MODULE__{
            name: atom(),
            version: String.t() | :stdlib | nil,
            module_name: module(),
            python_name: String.t(),
            pypi_package: String.t() | nil,
            docs_url: String.t() | nil,
            extras: [String.t()],
            include: [String.t()],
            exclude: [String.t()],
            streaming: [String.t()],
            submodules: boolean(),
            generate: generate_mode(),
            signature_sources: [atom() | String.t()] | nil,
            strict_signatures: boolean() | nil,
            min_signature_tier: atom() | String.t() | nil,
            stub_search_paths: [String.t()] | nil,
            use_typeshed: boolean() | nil,
            typeshed_path: String.t() | nil,
            stubgen: keyword() | nil
          }
  end

  @type t :: %__MODULE__{
          libraries: [Library.t()],
          auto_install: :never | :dev | :dev_test | :always,
          generated_dir: String.t(),
          generated_layout: :single | :split,
          metadata_dir: String.t(),
          helper_paths: [String.t()],
          helper_pack_enabled: boolean(),
          helper_allowlist: :all | [String.t()],
          inline_enabled: boolean(),
          strict: boolean(),
          verbose: boolean(),
          scan_paths: [String.t()],
          scan_exclude: [String.t()],
          introspector: keyword(),
          docs: keyword(),
          runtime_client: module(),
          ledger: keyword(),
          signature_sources: [atom() | String.t()],
          strict_signatures: boolean(),
          min_signature_tier: atom() | String.t(),
          stub_search_paths: [String.t()],
          use_typeshed: boolean(),
          typeshed_path: String.t() | nil,
          stubgen: keyword(),
          coverage_report: keyword()
        }

  @doc """
  Load config from mix.exs project config and Application env.

  Python dependencies are specified via the `python_deps` key in your mix.exs project:

      def project do
        [
          app: :my_app,
          version: "1.0.0",
          deps: deps(),
          python_deps: python_deps()
        ]
      end

      defp python_deps do
        [
          {:numpy, "1.26.0"},
          {:pandas, "2.0.0", include: ["DataFrame", "read_csv"]}
        ]
      end

  This approach mirrors how `deps/0` works and is compatible with all installation
  methods (Hex, path, git).
  """
  @spec load() :: t()
  def load do
    project_config = Mix.Project.config()
    python_deps = project_config[:python_deps] || []

    %__MODULE__{
      libraries: parse_libraries(python_deps),
      auto_install: Application.get_env(:snakebridge, :auto_install, :dev_test),
      generated_dir:
        Application.get_env(:snakebridge, :generated_dir, "lib/snakebridge_generated"),
      generated_layout: Application.get_env(:snakebridge, :generated_layout, :split),
      metadata_dir: Application.get_env(:snakebridge, :metadata_dir, ".snakebridge"),
      helper_paths: Application.get_env(:snakebridge, :helper_paths, ["priv/python/helpers"]),
      helper_pack_enabled: Application.get_env(:snakebridge, :helper_pack_enabled, true),
      helper_allowlist: Application.get_env(:snakebridge, :helper_allowlist, :all),
      inline_enabled: Application.get_env(:snakebridge, :inline_enabled, false),
      strict: env_flag(:strict, "SNAKEBRIDGE_STRICT", false),
      verbose: env_flag(:verbose, "SNAKEBRIDGE_VERBOSE", false),
      scan_paths: Application.get_env(:snakebridge, :scan_paths, ["lib"]),
      scan_exclude: Application.get_env(:snakebridge, :scan_exclude, []),
      introspector: Application.get_env(:snakebridge, :introspector, []),
      docs: Application.get_env(:snakebridge, :docs, []),
      runtime_client: Application.get_env(:snakebridge, :runtime_client, Snakepit),
      ledger: Application.get_env(:snakebridge, :ledger, []),
      signature_sources:
        Application.get_env(:snakebridge, :signature_sources, [
          :runtime,
          :text_signature,
          :runtime_hints,
          :stub,
          :stubgen,
          :variadic
        ]),
      strict_signatures: env_flag(:strict_signatures, "SNAKEBRIDGE_STRICT_SIGNATURES", false),
      min_signature_tier: Application.get_env(:snakebridge, :min_signature_tier, :runtime),
      stub_search_paths: Application.get_env(:snakebridge, :stub_search_paths, []),
      use_typeshed: Application.get_env(:snakebridge, :use_typeshed, false),
      typeshed_path: Application.get_env(:snakebridge, :typeshed_path),
      stubgen: Application.get_env(:snakebridge, :stubgen, []),
      coverage_report: Application.get_env(:snakebridge, :coverage_report, [])
    }
  end

  @doc false
  def parse_libraries(libraries) when is_list(libraries) do
    Enum.map(libraries, &parse_library/1)
  end

  # 3-tuple: {:numpy, "1.26.0", include: ["array"], submodules: true}
  defp parse_library({name, version, opts})
       when (is_binary(version) or version == :stdlib) and is_list(opts) do
    build_library(name, version, opts)
  end

  # 2-tuple with version: {:numpy, "1.26.0"} or {:math, :stdlib}
  defp parse_library({name, version}) when is_binary(version) or version == :stdlib do
    build_library(name, version, [])
  end

  # 2-tuple with opts (legacy): {:numpy, version: "1.26.0", include: [...]}
  defp parse_library({name, opts}) when is_list(opts) do
    version = Keyword.get(opts, :version)
    build_library(name, version, opts)
  end

  # Atom only: :math (stdlib, no version)
  defp parse_library(name) when is_atom(name) do
    build_library(name, nil, [])
  end

  # String only: "math" (stdlib, no version)
  defp parse_library(name) when is_binary(name) do
    build_library(String.to_atom(name), nil, [])
  end

  defp build_library(name, version, opts) do
    module_name = Keyword.get(opts, :module_name, default_module_name(name))
    python_name = Keyword.get(opts, :python_name, Atom.to_string(name))
    extras = Keyword.get(opts, :extras, [])
    generate = Keyword.get(opts, :generate, :used)

    validate_generate_option!(generate, name)

    %Library{
      name: name,
      version: version,
      module_name: module_name,
      python_name: python_name,
      pypi_package: Keyword.get(opts, :pypi_package),
      docs_url: Keyword.get(opts, :docs_url),
      extras: List.wrap(extras),
      include: Keyword.get(opts, :include, []),
      exclude: Keyword.get(opts, :exclude, []),
      streaming: Keyword.get(opts, :streaming, []),
      submodules: Keyword.get(opts, :submodules, false),
      generate: generate,
      signature_sources: Keyword.get(opts, :signature_sources),
      strict_signatures: Keyword.get(opts, :strict_signatures),
      min_signature_tier: Keyword.get(opts, :min_signature_tier),
      stub_search_paths: Keyword.get(opts, :stub_search_paths),
      use_typeshed: Keyword.get(opts, :use_typeshed),
      typeshed_path: Keyword.get(opts, :typeshed_path),
      stubgen: Keyword.get(opts, :stubgen)
    }
  end

  defp validate_generate_option!(generate, _name) when generate in [:all, :used], do: :ok

  defp validate_generate_option!(invalid, name) do
    raise ArgumentError, """
    Invalid generate option for #{inspect(name)}: #{inspect(invalid)}

    The generate option must be :all or :used.

    Examples:
      {:dspy, "2.6.5", generate: :all}   # Generate all public symbols
      {:numpy, "1.26.0", generate: :used} # Only generate used symbols (default)
    """
  end

  defp default_module_name(name) do
    name
    |> Atom.to_string()
    |> Macro.camelize()
    |> then(&Module.concat([&1]))
  end

  defp env_flag(config_key, env_var, default) do
    case System.get_env(env_var) do
      nil -> Application.get_env(:snakebridge, config_key, default)
      value -> value in ["1", "true", "TRUE", "yes", "YES"]
    end
  end
end
