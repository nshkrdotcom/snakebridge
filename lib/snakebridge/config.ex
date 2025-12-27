defmodule SnakeBridge.Config do
  @moduledoc """
  Compile-time configuration for SnakeBridge.
  """

  defstruct [
    :libraries,
    :auto_install,
    :generated_dir,
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
    :ledger
  ]

  defmodule Library do
    @moduledoc """
    Configuration struct for a single Python library binding.
    """

    defstruct [
      :name,
      :version,
      :module_name,
      :python_name,
      :pypi_package,
      :extras,
      include: [],
      exclude: [],
      streaming: [],
      submodules: false
    ]

    @type t :: %__MODULE__{
            name: atom(),
            version: String.t() | :stdlib | nil,
            module_name: module(),
            python_name: String.t(),
            pypi_package: String.t() | nil,
            extras: [String.t()],
            include: [String.t()],
            exclude: [String.t()],
            streaming: [String.t()],
            submodules: boolean()
          }
  end

  @type t :: %__MODULE__{
          libraries: [Library.t()],
          auto_install: :never | :dev | :always,
          generated_dir: String.t(),
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
          ledger: keyword()
        }

  @doc """
  Load config from mix.exs dependency options and Application env.
  """
  @spec load() :: t()
  def load do
    deps = Mix.Project.config()[:deps] || []

    opts =
      deps
      |> Enum.find_value([], fn
        {:snakebridge, opts} when is_list(opts) -> opts
        {:snakebridge, _req, opts} when is_list(opts) -> opts
        _ -> nil
      end)
      |> List.wrap()

    %__MODULE__{
      libraries: parse_libraries(Keyword.get(opts, :libraries, [])),
      auto_install: Application.get_env(:snakebridge, :auto_install, :dev),
      generated_dir: Keyword.get(opts, :generated_dir, "lib/snakebridge_generated"),
      metadata_dir: Keyword.get(opts, :metadata_dir, ".snakebridge"),
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
      ledger: Application.get_env(:snakebridge, :ledger, [])
    }
  end

  @doc false
  def parse_libraries(libraries) when is_list(libraries) do
    Enum.map(libraries, &parse_library/1)
  end

  defp parse_library({name, version}) when is_binary(version) or version == :stdlib do
    build_library(name, version, [])
  end

  defp parse_library({name, opts}) when is_list(opts) do
    version = Keyword.get(opts, :version)
    build_library(name, version, opts)
  end

  defp parse_library(name) when is_atom(name) do
    build_library(name, nil, [])
  end

  defp parse_library(name) when is_binary(name) do
    build_library(String.to_atom(name), nil, [])
  end

  defp build_library(name, version, opts) do
    module_name = Keyword.get(opts, :module_name, default_module_name(name))
    python_name = Keyword.get(opts, :python_name, Atom.to_string(name))
    extras = Keyword.get(opts, :extras, [])

    %Library{
      name: name,
      version: version,
      module_name: module_name,
      python_name: python_name,
      pypi_package: Keyword.get(opts, :pypi_package),
      extras: List.wrap(extras),
      include: Keyword.get(opts, :include, []),
      exclude: Keyword.get(opts, :exclude, []),
      streaming: Keyword.get(opts, :streaming, []),
      submodules: Keyword.get(opts, :submodules, false)
    }
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
