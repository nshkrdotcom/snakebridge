defmodule SnakeBridge.ConfigHelper do
  @moduledoc """
  Configuration helper for auto-configuring Snakepit to work with SnakeBridge.

  ## Usage

  In your `config/config.exs`, replace manual snakepit configuration with:

      import Config

      # Auto-configure snakepit for snakebridge
      for {key, value} <- SnakeBridge.ConfigHelper.snakepit_config() do
        config :snakepit, [{key, value}]
      end

  Or for a cleaner look, use the convenience macro in `config/runtime.exs`:

      import Config
      SnakeBridge.ConfigHelper.configure_snakepit!()

  Multi-pool configuration (with per-pool affinity):

      import Config
      SnakeBridge.ConfigHelper.configure_snakepit!(
        pools: [
          %{name: :hint_pool, pool_size: 2, affinity: :hint},
          %{name: :strict_pool, pool_size: 2, affinity: :strict_queue}
        ]
      )

  ## How It Works

  The helper looks for a Python venv in these locations (in order):
  1. `$SNAKEBRIDGE_VENV` environment variable
  2. `:snakebridge, :venv_path` config
  3. Snakepit-managed venv (default: `priv/snakepit/python/venv`)
  4. `.venv` in the current project root
  5. `.venv` in SnakeBridge's installation directory (for path deps or hex deps)

  For PYTHONPATH, it includes:
  - Snakepit's priv/python directory
  - SnakeBridge's priv/python directory
  """

  @doc """
  Returns snakepit configuration for use with SnakeBridge.

  Use this in `config/config.exs`:

      for {key, value} <- SnakeBridge.ConfigHelper.snakepit_config() do
        config :snakepit, [{key, value}]
      end

  Options:
  - `:pool_size` - Number of Python workers (default: 2)
  - `:venv_path` - Explicit path to venv directory
  - `:affinity` - Snakepit session affinity mode (`:hint`, `:strict_queue`, `:strict_fail_fast`)
  - `:pools` - Multi-pool config list (maps or keyword lists); defaults apply per pool
  """
  @spec snakepit_config(keyword()) :: keyword()
  def snakepit_config(opts \\ []) do
    python_executable = resolve_python_executable(opts)
    pythonpath = build_pythonpath(opts)
    pool_size = Keyword.get(opts, :pool_size, 2)
    affinity = Keyword.get(opts, :affinity)
    pools = Keyword.get(opts, :pools)

    adapter_env =
      if pythonpath do
        %{"PYTHONPATH" => pythonpath}
      else
        %{}
      end

    base_pool_config =
      %{
        pool_size: pool_size,
        adapter_args: ["--adapter", "snakebridge_adapter.SnakeBridgeAdapter"],
        adapter_env: adapter_env
      }
      |> maybe_put_affinity(affinity)

    base_config = [
      pooling_enabled: true,
      adapter_module: Snakepit.Adapters.GRPCPython
    ]

    base_config =
      if is_list(pools) do
        normalized_pools = normalize_pools(pools, base_pool_config, affinity)
        Keyword.put(base_config, :pools, normalized_pools)
      else
        Keyword.put(base_config, :pool_config, base_pool_config)
      end

    if python_executable do
      Keyword.put(base_config, :python_executable, python_executable)
    else
      base_config
    end
  end

  @doc """
  Auto-configures Snakepit for use with SnakeBridge at runtime.

  Best used in `config/runtime.exs`:

      import Config
      SnakeBridge.ConfigHelper.configure_snakepit!()

  This applies configuration via Application.put_env, which works in runtime.exs.
  """
  def configure_snakepit!(opts \\ []) do
    align_otp_logger_level()

    for {key, value} <- snakepit_config(opts) do
      # Only set if not already configured
      unless Application.get_env(:snakepit, key) do
        Application.put_env(:snakepit, key, value)
      end
    end

    :ok
  end

  @doc """
  Returns configuration values for debugging.
  """
  def debug_config do
    %{
      python_executable: resolve_python_executable([]),
      pythonpath: build_pythonpath([]),
      snakebridge_root: snakebridge_root(),
      snakepit_priv: snakepit_priv_python(),
      snakebridge_priv: snakebridge_priv_python(),
      snakepit_env_dir: snakepit_env_dir(),
      snakepit_env_python: snakepit_env_python()
    }
  end

  # -- Private --

  defp resolve_python_executable(opts) do
    cond do
      # 1. Environment variable override
      env_venv = System.get_env("SNAKEBRIDGE_VENV") ->
        venv_python(env_venv)

      # 2. Explicit config
      config_path = Keyword.get(opts, :venv_path) ->
        venv_python(config_path)

      # 3. Application config
      app_venv = Application.get_env(:snakebridge, :venv_path) ->
        venv_python(app_venv)

      # 4. Snakepit-managed venv (auto-installed with mix snakebridge.setup)
      snakepit_env = snakepit_env_python() ->
        snakepit_env

      # 5. .venv in current project
      project_venv = project_venv_python() ->
        project_venv

      # 6. .venv in snakebridge's directory
      snakebridge_venv = snakebridge_venv_python() ->
        snakebridge_venv

      # 7. Fall back to system python3
      true ->
        nil
    end
  end

  defp venv_python(venv_dir) do
    candidates = [
      Path.join([venv_dir, "bin", "python3"]),
      Path.join([venv_dir, "bin", "python"]),
      Path.join([venv_dir, "Scripts", "python.exe"]),
      Path.join([venv_dir, "Scripts", "python"])
    ]

    Enum.find(candidates, &File.exists?/1)
  end

  defp project_venv_python do
    venv_dir = Path.join(project_root(), ".venv")

    if File.dir?(venv_dir) do
      venv_python(venv_dir)
    else
      nil
    end
  end

  defp snakebridge_venv_python do
    case snakebridge_root() do
      nil ->
        nil

      root ->
        venv_dir = Path.join(root, ".venv")

        if File.dir?(venv_dir) do
          venv_python(venv_dir)
        else
          nil
        end
    end
  end

  defp snakepit_env_python do
    case snakepit_env_dir() do
      nil -> nil
      venv_dir -> venv_python(venv_dir)
    end
  end

  defp snakepit_env_dir do
    python_packages =
      :snakepit
      |> Application.get_env(:python_packages, [])
      |> normalize_config_input()

    case Map.get(python_packages, :env_dir) do
      false ->
        nil

      nil ->
        default_snakepit_env_dir()

      value ->
        Path.expand(value, project_root())
    end
  end

  defp default_snakepit_env_dir do
    python_config =
      :snakepit
      |> Application.get_env(:python, [])
      |> normalize_config_input()

    runtime_dir = Map.get(python_config, :runtime_dir, "priv/snakepit/python")
    Path.expand(Path.join(runtime_dir, "venv"), project_root())
  end

  defp build_pythonpath(_opts) do
    path_sep = if match?({:win32, _}, :os.type()), do: ";", else: ":"

    paths =
      [
        System.get_env("PYTHONPATH"),
        snakepit_priv_python(),
        snakebridge_priv_python()
      ]
      |> Enum.reject(fn path -> is_nil(path) or path == "" end)
      |> Enum.filter(&File.dir?/1)
      |> Enum.uniq()

    if paths == [] do
      nil
    else
      Enum.join(paths, path_sep)
    end
  end

  defp snakepit_priv_python do
    case :code.priv_dir(:snakepit) do
      {:error, _} ->
        # Snakepit not loaded yet, try deps path
        Path.join([project_root(), "deps", "snakepit", "priv", "python"])

      priv_dir ->
        Path.join(to_string(priv_dir), "python")
    end
  end

  defp snakebridge_priv_python do
    case snakebridge_root() do
      nil -> nil
      root -> Path.join([root, "priv", "python"])
    end
  end

  defp align_otp_logger_level do
    level = Application.get_env(:logger, :level, :warning)
    :logger.set_primary_config(:level, normalize_otp_level(level))
  end

  defp normalize_otp_level(:warn), do: :warning

  defp normalize_otp_level(level)
       when level in [:debug, :info, :notice, :warning, :error, :critical, :alert, :emergency],
       do: level

  defp normalize_otp_level(_), do: :warning

  defp normalize_pools(pools, base_pool_config, affinity) do
    Enum.map(pools, fn pool ->
      pool =
        pool
        |> normalize_pool_input()
        |> Map.put_new(:pool_size, base_pool_config.pool_size)
        |> Map.put_new(:adapter_args, base_pool_config.adapter_args)
        |> Map.put(
          :adapter_env,
          merge_adapter_env(base_pool_config.adapter_env, Map.get(pool, :adapter_env))
        )

      pool
      |> maybe_put_affinity(affinity)
    end)
  end

  defp normalize_pool_input(%{} = pool), do: pool
  defp normalize_pool_input(pool) when is_list(pool), do: Map.new(pool)
  defp normalize_pool_input(_), do: %{}

  defp normalize_config_input(nil), do: %{}
  defp normalize_config_input(%{} = map), do: map
  defp normalize_config_input(list) when is_list(list), do: Map.new(list)
  defp normalize_config_input(_), do: %{}

  defp merge_adapter_env(base_env, nil), do: base_env

  defp merge_adapter_env(base_env, env) when is_map(env) do
    Map.merge(base_env, env)
  end

  defp merge_adapter_env(base_env, env) when is_list(env) do
    Map.merge(base_env, Map.new(env))
  end

  defp merge_adapter_env(base_env, _env), do: base_env

  defp maybe_put_affinity(pool_config, nil), do: pool_config

  defp maybe_put_affinity(pool_config, affinity),
    do: Map.put_new(pool_config, :affinity, affinity)

  defp snakebridge_root do
    case :code.priv_dir(:snakebridge) do
      {:error, _} ->
        # SnakeBridge not loaded yet, try common locations
        project = project_root()

        cond do
          # Path dependency at ../snakebridge
          File.dir?(Path.join([project, "..", "snakebridge", "priv"])) ->
            Path.expand(Path.join(project, "../snakebridge"))

          # Hex dependency in deps
          File.dir?(Path.join([project, "deps", "snakebridge", "priv"])) ->
            Path.join([project, "deps", "snakebridge"])

          true ->
            nil
        end

      priv_dir ->
        # priv_dir may be a symlink (common with path deps in _build)
        # Follow symlinks to find the actual source location
        priv_dir
        |> to_string()
        |> resolve_symlinks()
        |> Path.dirname()
    end
  end

  # Follow symlinks to get the real path
  defp resolve_symlinks(path) do
    case File.read_link(path) do
      {:ok, target} ->
        # Symlink target may be relative, resolve it
        resolved =
          if Path.type(target) == :relative do
            path
            |> Path.dirname()
            |> Path.join(target)
            |> Path.expand()
          else
            target
          end

        # Recurse in case of chained symlinks
        resolve_symlinks(resolved)

      {:error, _} ->
        # Not a symlink, return as-is
        Path.expand(path)
    end
  end

  defp project_root do
    # During config loading, File.cwd!() is the project root
    File.cwd!()
  end
end
