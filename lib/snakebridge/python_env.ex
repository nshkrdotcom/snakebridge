defmodule SnakeBridge.PythonEnv do
  @moduledoc """
  Compile-time orchestrator for Python environment provisioning.
  """

  alias SnakeBridge.{Config, EnvironmentError}

  @type requirement :: String.t()
  @project_requirements_path ["priv", "python", "requirements.txt"]

  @doc """
  Ensures the Python environment is ready for introspection.

  In dev with auto_install enabled, installs missing packages.
  In strict mode, verifies the environment without installing.
  """
  @spec ensure!(Config.t()) :: :ok | no_return()
  def ensure!(config) do
    sync_project_requirements!(config)

    cond do
      strict_mode?(config) ->
        verify_environment!(config)

      auto_install_enabled?(config) ->
        do_ensure!(config)

      true ->
        verify_environment!(config)
    end
  end

  @doc """
  Converts library config to PEP-440 requirement strings.

  Skips stdlib libraries and applies pypi_package and extras overrides.
  """
  @spec derive_requirements([Config.Library.t()]) :: [requirement()]
  def derive_requirements(libraries) when is_list(libraries) do
    libraries
    |> Enum.reject(&stdlib_library?/1)
    |> Enum.map(&library_to_requirement/1)
  end

  @doc false
  @spec sync_project_requirements!(Config.t()) :: :ok
  def sync_project_requirements!(config) do
    if sync_project_requirements?() do
      requirements = derive_requirements(config.libraries)
      path = project_requirements_path()
      contents = render_project_requirements(requirements)
      write_project_requirements(path, contents)
    end

    :ok
  end

  @doc """
  Checks packages are installed without installing.
  """
  @spec verify_environment!(Config.t()) :: :ok | no_return()
  def verify_environment!(config) do
    requirements = derive_requirements(config.libraries)

    case python_packages_module().check_installed(requirements, python_packages_opts([])) do
      {:ok, :all_installed} ->
        :ok

      {:ok, {:missing, missing}} ->
        raise EnvironmentError,
          message: "Missing Python packages: #{inspect(missing)}",
          missing_packages: missing,
          suggestion: "Run: mix snakebridge.setup"
    end
  end

  defp do_ensure!(config) do
    ensure_python_runtime!()
    ensure_snakebridge_requirements!(config)
    ensure_snakepit_adapter!()
    ensure_snakepit_requirements!(config)
    requirements = derive_requirements(config.libraries)

    if requirements != [] do
      python_packages_module().ensure!(
        {:list, requirements},
        python_packages_opts(quiet: !config.verbose)
      )
    end

    :ok
  end

  defp ensure_snakepit_requirements!(config) do
    if python_packages_module() == Snakepit.PythonPackages do
      case snakepit_requirements_path() do
        nil ->
          :ok

        path ->
          python_packages_module().ensure!(
            {:file, path},
            python_packages_opts(quiet: !config.verbose)
          )
      end
    else
      :ok
    end
  end

  defp ensure_snakebridge_requirements!(config) do
    case snakebridge_requirements_path() do
      nil ->
        :ok

      path ->
        python_packages_module().ensure!(
          {:file, path},
          python_packages_opts(quiet: !config.verbose)
        )
    end
  end

  defp ensure_python_runtime! do
    python_config = Application.get_env(:snakepit, :python, [])

    if Keyword.get(python_config, :managed, false) do
      python_runtime_module().install_managed(SnakeBridge.PythonRuntimeRunner, [])
    end

    :ok
  end

  defp auto_install_enabled?(config) do
    case auto_install_setting(config) do
      :never -> false
      :always -> true
      :dev -> Mix.env() == :dev
      :dev_test -> Mix.env() in [:dev, :test]
    end
  end

  defp auto_install_setting(config) do
    case System.get_env("SNAKEBRIDGE_AUTO_INSTALL") do
      "never" -> :never
      "always" -> :always
      "dev" -> :dev
      "dev_test" -> :dev_test
      nil -> config.auto_install || :dev_test
      _ -> config.auto_install || :dev_test
    end
  end

  defp strict_mode?(config) do
    System.get_env("SNAKEBRIDGE_STRICT") == "1" || config.strict == true
  end

  defp stdlib_library?(%Config.Library{version: :stdlib}), do: true
  defp stdlib_library?(_), do: false

  defp library_to_requirement(library) do
    package = library.pypi_package || library.python_name || Atom.to_string(library.name)
    extras = List.wrap(library.extras || [])
    version = translate_version(library.version)

    base =
      if extras == [] do
        package
      else
        package <> "[" <> Enum.join(extras, ",") <> "]"
      end

    if version do
      base <> version
    else
      base
    end
  end

  defp translate_version(nil), do: nil
  defp translate_version(:stdlib), do: nil

  defp translate_version(v) when is_binary(v) do
    v = String.trim(v)

    if String.starts_with?(v, ["~=", ">=", "<=", "==", "!="]) do
      v
    else
      case Regex.run(~r/^~>\s*(.+)$/, v) do
        [_, ver] -> "~=#{ver}"
        nil -> "==#{v}"
      end
    end
  end

  defp python_packages_module do
    Application.get_env(:snakebridge, :python_packages, Snakepit.PythonPackages)
  end

  defp python_packages_opts(opts) do
    if python_packages_module() == Snakepit.PythonPackages do
      Keyword.put_new(opts, :runner, SnakeBridge.PythonPackagesRunner)
    else
      opts
    end
  end

  defp python_runtime_module do
    Application.get_env(:snakebridge, :python_runtime, Snakepit.PythonRuntime)
  end

  defp snakepit_requirements_path do
    case :code.priv_dir(:snakepit) do
      {:error, _} ->
        nil

      priv_dir ->
        path = Path.join([to_string(priv_dir), "python", "requirements.txt"])
        if File.exists?(path), do: path, else: nil
    end
  end

  defp snakebridge_requirements_path do
    case :code.priv_dir(:snakebridge) do
      {:error, _} ->
        nil

      priv_dir ->
        path = Path.join([to_string(priv_dir), "python", "requirements.txt"])
        if File.exists?(path), do: path, else: nil
    end
  end

  defp ensure_snakepit_adapter! do
    if is_list(Application.get_env(:snakepit, :pools)) do
      :ok
    else
      adapter_module = Application.get_env(:snakepit, :adapter_module)

      if is_nil(adapter_module) do
        Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.GRPCPython)
      end

      pool_config =
        :snakepit
        |> Application.get_env(:pool_config, %{})
        |> normalize_config_input()

      adapter_args = Map.get(pool_config, :adapter_args, [])

      if adapter_args_missing?(adapter_args) do
        updated = Map.put(pool_config, :adapter_args, default_adapter_args())
        Application.put_env(:snakepit, :pool_config, updated)
      end

      :ok
    end
  end

  defp adapter_args_missing?(adapter_args) when is_list(adapter_args) do
    not Enum.any?(adapter_args, fn arg ->
      is_binary(arg) and (arg == "--adapter" or String.starts_with?(arg, "--adapter="))
    end)
  end

  defp adapter_args_missing?(_), do: true

  defp default_adapter_args do
    ["--adapter", "snakebridge_adapter.SnakeBridgeAdapter"]
  end

  defp sync_project_requirements? do
    enabled = Application.get_env(:snakebridge, :sync_project_requirements, true)
    root_override = Application.get_env(:snakebridge, :requirements_project_root)

    app =
      if Code.ensure_loaded?(Mix.Project) do
        Mix.Project.config()[:app]
      end

    enabled and (root_override || (is_atom(app) and app != :snakebridge))
  end

  defp project_requirements_path do
    root =
      Application.get_env(:snakebridge, :requirements_project_root) ||
        project_root()

    Path.join([root | @project_requirements_path])
  end

  defp project_root do
    if Code.ensure_loaded?(Mix.Project) do
      case Mix.Project.project_file() do
        nil -> File.cwd!()
        path -> Path.dirname(path)
      end
    else
      File.cwd!()
    end
  end

  defp render_project_requirements(requirements) do
    header = [
      "# Generated by SnakeBridge from python_deps in mix.exs.",
      "# Edit python_deps instead of this file.",
      ""
    ]

    Enum.join(header ++ requirements, "\n") <> "\n"
  end

  defp write_project_requirements(path, contents) do
    case File.read(path) do
      {:ok, ^contents} ->
        :ok

      _ ->
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, contents)
    end
  end

  defp normalize_config_input(nil), do: %{}
  defp normalize_config_input(%{} = map), do: map
  defp normalize_config_input(list) when is_list(list), do: Map.new(list)
  defp normalize_config_input(_), do: %{}
end
