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
    :scan_extensions,
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
    - `:module_mode` - Controls which Python submodules are generated when `generate: :all`:
      - `:root` / `:light` / `:top` - Only the root module
      - `:exports` / `:api` - Only the root module, plus submodules explicitly exported
        by the root module via `__all__` (avoids walking large internal trees)
      - `:public` / `:standard` - Discover submodules and keep public API modules
      - `:explicit` - Discover submodules and keep only modules/packages that explicitly
        define `__all__` (smallest “discover” mode; use `module_include` for overrides)
      - `:docs` / `:manifest` - Generate a docs-defined public surface from a manifest file
      - `:all` / `:nuclear` - Discover all submodules (including private)
      - `{:only, ["linalg", "fft"]}` - Explicit submodule allowlist
    - `:submodules` - When `true`, introspect all submodules (can generate thousands of files)
    - `:public_api` - When `true` with `submodules: true`, only include modules with explicit
      public API (`__all__` defined or classes defined in the module). This filters out internal
      implementation modules, typically reducing generated files by 90%+.
    - `:module_include` - Extra submodules to include (relative to the library root)
    - `:module_exclude` - Submodules to exclude (relative to the library root)
    - `:module_depth` - Limit discovery depth (e.g. 1 = only direct children)
    - `:docs_url` - Explicit documentation URL for third-party libraries
    - `:docs_manifest` - Path to a SnakeBridge docs manifest JSON file (used with `module_mode: :docs`)
    - `:docs_profile` - Profile key inside `docs_manifest` (`:summary`, `:full`, or custom string)
    - `:class_method_scope` - Controls how class methods are discovered during introspection:
      - `:all` (default) - include inherited methods (can be huge for tensor-like bases)
      - `:defined` - only methods defined on the class itself (plus `__init__`)
    - `:max_class_methods` - Guardrail for class method enumeration. When `class_method_scope: :all`
      would exceed this limit, SnakeBridge falls back to `:defined` for that class.
    - `:on_not_found` - Behavior when a requested symbol is not present in the current Python env:
      - `:error` - fail compilation (recommended for `generate: :used`)
      - `:stub` - generate deterministic stubs and continue (recommended for docs-derived surfaces)
    """

    defstruct [
      :name,
      :version,
      :module_name,
      :python_name,
      :pypi_package,
      :docs_url,
      :docs_manifest,
      :docs_profile,
      :extras,
      :module_mode,
      :module_include,
      :module_exclude,
      :module_depth,
      :class_method_scope,
      :max_class_methods,
      :on_not_found,
      include: [],
      exclude: [],
      streaming: [],
      submodules: false,
      public_api: false,
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
    @type module_mode ::
            :root | :exports | :public | :explicit | :docs | :all | {:only, [String.t()]}
    @type class_method_scope :: :all | :defined
    @type on_not_found :: :error | :stub

    @type t :: %__MODULE__{
            name: atom(),
            version: String.t() | :stdlib | nil,
            module_name: module(),
            python_name: String.t(),
            pypi_package: String.t() | nil,
            docs_url: String.t() | nil,
            docs_manifest: String.t() | nil,
            docs_profile: String.t() | nil,
            extras: [String.t()],
            module_mode: module_mode() | nil,
            module_include: [String.t()],
            module_exclude: [String.t()],
            module_depth: pos_integer() | nil,
            class_method_scope: class_method_scope() | nil,
            max_class_methods: non_neg_integer() | nil,
            on_not_found: on_not_found() | nil,
            include: [String.t()],
            exclude: [String.t()],
            streaming: [String.t()],
            submodules: boolean(),
            public_api: boolean(),
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
          auto_install: :never | :dev | :dev_test | :always | nil,
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
          scan_extensions: [String.t()],
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
      scan_extensions: Application.get_env(:snakebridge, :scan_extensions, [".ex"]),
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
    module_mode = normalize_module_mode(Keyword.get(opts, :module_mode))
    module_include = normalize_module_list(Keyword.get(opts, :module_include, []))
    module_exclude = normalize_module_list(Keyword.get(opts, :module_exclude, []))
    module_depth = Keyword.get(opts, :module_depth)
    docs_manifest = Keyword.get(opts, :docs_manifest)
    docs_profile = normalize_docs_profile(Keyword.get(opts, :docs_profile))
    class_method_scope = normalize_class_method_scope(Keyword.get(opts, :class_method_scope))
    max_class_methods = Keyword.get(opts, :max_class_methods)
    on_not_found = normalize_on_not_found(Keyword.get(opts, :on_not_found))

    validate_generate_option!(generate, name)
    validate_module_mode!(module_mode, name)
    validate_module_depth!(module_depth, name)
    validate_docs_manifest!(module_mode, docs_manifest, name)
    validate_class_method_scope!(class_method_scope, name)
    validate_max_class_methods!(max_class_methods, name)
    validate_on_not_found!(on_not_found, name)

    %Library{
      name: name,
      version: version,
      module_name: module_name,
      python_name: python_name,
      pypi_package: Keyword.get(opts, :pypi_package),
      docs_url: Keyword.get(opts, :docs_url),
      docs_manifest: docs_manifest,
      docs_profile: docs_profile,
      extras: List.wrap(extras),
      module_mode: module_mode,
      module_include: module_include,
      module_exclude: module_exclude,
      module_depth: normalize_module_depth(module_depth),
      class_method_scope: class_method_scope,
      max_class_methods: normalize_max_class_methods(max_class_methods),
      on_not_found: on_not_found,
      include: Keyword.get(opts, :include, []),
      exclude: Keyword.get(opts, :exclude, []),
      streaming: Keyword.get(opts, :streaming, []),
      submodules: Keyword.get(opts, :submodules, false),
      public_api: Keyword.get(opts, :public_api, false),
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
      {:mylib, "1.0.0", generate: :all}   # Generate all public symbols
      {:numpy, "1.26.0", generate: :used} # Only generate used symbols (default)
    """
  end

  defp normalize_module_mode(nil), do: nil
  defp normalize_module_mode(:light), do: :root
  defp normalize_module_mode(:top), do: :root
  defp normalize_module_mode(:root), do: :root
  defp normalize_module_mode(:api), do: :exports
  defp normalize_module_mode(:exports), do: :exports
  defp normalize_module_mode(:explicit), do: :explicit
  defp normalize_module_mode(:manifest), do: :docs
  defp normalize_module_mode(:docs), do: :docs
  defp normalize_module_mode(:standard), do: :public
  defp normalize_module_mode(:public), do: :public
  defp normalize_module_mode(:full), do: :all
  defp normalize_module_mode(:nuclear), do: :all
  defp normalize_module_mode(:all), do: :all

  defp normalize_module_mode({:only, list}) when is_list(list),
    do: {:only, normalize_module_list(list)}

  defp normalize_module_mode(other), do: other

  defp normalize_module_list(nil), do: []
  defp normalize_module_list(list) when is_list(list), do: Enum.map(list, &to_string/1)
  defp normalize_module_list(value) when is_binary(value), do: [value]
  defp normalize_module_list(_), do: []

  defp normalize_module_depth(nil), do: nil
  defp normalize_module_depth(value) when is_integer(value) and value > 0, do: value
  defp normalize_module_depth(_), do: nil

  defp validate_module_depth!(nil, _name), do: :ok

  defp validate_module_depth!(value, _name) when is_integer(value) and value > 0, do: :ok

  defp validate_module_depth!(invalid, name) do
    raise ArgumentError, """
    Invalid module_depth option for #{inspect(name)}: #{inspect(invalid)}

    module_depth must be a positive integer (e.g. 1 or 2).
    """
  end

  defp validate_module_mode!(nil, _name), do: :ok

  defp validate_module_mode!(mode, _name)
       when mode in [:root, :exports, :public, :explicit, :docs, :all],
       do: :ok

  defp validate_module_mode!({:only, list}, _name) when is_list(list), do: :ok

  defp validate_module_mode!(invalid, name) do
    raise ArgumentError, """
    Invalid module_mode option for #{inspect(name)}: #{inspect(invalid)}

    module_mode must be one of:
      :root | :light | :top
      :exports | :api
      :public | :standard
      :explicit
      :docs | :manifest
      :all | :full | :nuclear
      {:only, ["submodule", "submodule.nested"]}
    """
  end

  defp normalize_docs_profile(nil), do: nil
  defp normalize_docs_profile(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_docs_profile(value) when is_binary(value), do: value
  defp normalize_docs_profile(_), do: nil

  defp validate_docs_manifest!(:docs, nil, name) do
    raise ArgumentError, """
    Missing :docs_manifest for #{inspect(name)}.

    When using `module_mode: :docs`, you must provide a docs manifest JSON path:

        {:mylib, "1.0.0",
          generate: :all,
          module_mode: :docs,
          docs_manifest: "priv/snakebridge/mylib.docs.json",
          docs_profile: :summary}
    """
  end

  defp validate_docs_manifest!(_mode, _manifest, _name), do: :ok

  defp normalize_class_method_scope(nil), do: nil
  defp normalize_class_method_scope(:all), do: :all
  defp normalize_class_method_scope(:defined), do: :defined
  defp normalize_class_method_scope(:declared), do: :defined
  defp normalize_class_method_scope(:declared_only), do: :defined
  defp normalize_class_method_scope(:defined_only), do: :defined
  defp normalize_class_method_scope(_), do: nil

  defp validate_class_method_scope!(nil, _name), do: :ok
  defp validate_class_method_scope!(scope, _name) when scope in [:all, :defined], do: :ok

  defp validate_class_method_scope!(invalid, name) do
    raise ArgumentError, """
    Invalid class_method_scope option for #{inspect(name)}: #{inspect(invalid)}

    class_method_scope must be :all or :defined.
    """
  end

  defp normalize_max_class_methods(nil), do: nil
  defp normalize_max_class_methods(value) when is_integer(value) and value >= 0, do: value
  defp normalize_max_class_methods(_), do: nil

  defp validate_max_class_methods!(nil, _name), do: :ok
  defp validate_max_class_methods!(value, _name) when is_integer(value) and value >= 0, do: :ok

  defp validate_max_class_methods!(invalid, name) do
    raise ArgumentError, """
    Invalid max_class_methods option for #{inspect(name)}: #{inspect(invalid)}

    max_class_methods must be a non-negative integer (e.g. 1000). Use 0 to disable the guardrail.
    """
  end

  defp normalize_on_not_found(nil), do: nil
  defp normalize_on_not_found(:error), do: :error
  defp normalize_on_not_found(:stub), do: :stub
  defp normalize_on_not_found(_), do: nil

  defp validate_on_not_found!(nil, _name), do: :ok
  defp validate_on_not_found!(mode, _name) when mode in [:error, :stub], do: :ok

  defp validate_on_not_found!(invalid, name) do
    raise ArgumentError, """
    Invalid on_not_found option for #{inspect(name)}: #{inspect(invalid)}

    on_not_found must be :error or :stub.
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
