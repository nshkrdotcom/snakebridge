defmodule SnakeBridge.ConfigHelperTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.ConfigHelper

  test "snakepit_config includes affinity in pool_config" do
    config = ConfigHelper.snakepit_config(pool_size: 3, affinity: :strict_queue)

    pool_config = Keyword.fetch!(config, :pool_config)

    assert pool_config.pool_size == 3
    assert pool_config.affinity == :strict_queue
  end

  test "snakepit_config builds pools with defaults and affinity" do
    pools = [
      %{name: :hint_pool, affinity: :hint},
      %{name: :strict_pool}
    ]

    config = ConfigHelper.snakepit_config(pool_size: 2, affinity: :strict_queue, pools: pools)

    assert Keyword.has_key?(config, :pools)
    refute Keyword.has_key?(config, :pool_config)

    [hint_pool, strict_pool] = Keyword.fetch!(config, :pools)

    assert hint_pool.name == :hint_pool
    assert hint_pool.affinity == :hint
    assert hint_pool.pool_size == 2
    assert is_list(hint_pool.adapter_args)
    assert is_map(hint_pool.adapter_env)

    assert strict_pool.name == :strict_pool
    assert strict_pool.affinity == :strict_queue
    assert strict_pool.pool_size == 2
    assert is_list(strict_pool.adapter_args)
    assert is_map(strict_pool.adapter_env)
  end

  test "snakepit_config prefers snakepit-managed venv when available" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "snakebridge_config_helper_#{System.unique_integer([:positive])}"
      )

    venv_dir = Path.join(tmp_dir, "venv")
    python_path = Path.join([venv_dir, "bin", "python3"])
    File.mkdir_p!(Path.dirname(python_path))
    File.write!(python_path, "#!/usr/bin/env python3\n")
    File.chmod!(python_path, 0o755)

    restore_venv_env = SnakeBridge.Env.put_system_env_override("SNAKEBRIDGE_VENV", nil)
    restore_snakebridge_venv = SnakeBridge.Env.put_app_env_override(:snakebridge, :venv_path, nil)

    restore_snakepit_python_packages =
      SnakeBridge.Env.put_app_env_override(:snakepit, :python_packages, env_dir: venv_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
      restore_snakepit_python_packages.()
      restore_snakebridge_venv.()
      restore_venv_env.()
    end)

    config = ConfigHelper.snakepit_config()
    assert Keyword.get(config, :python_executable) == python_path
  end

  test "snakepit_config merges adapter_env into pool_config" do
    config =
      ConfigHelper.snakepit_config(
        pool_size: 1,
        adapter_env: %{"EXAMPLE_ENABLE_MULTIPROCESSING" => "1"}
      )

    pool_config = Keyword.fetch!(config, :pool_config)
    assert is_map(pool_config.adapter_env)
    assert pool_config.adapter_env["EXAMPLE_ENABLE_MULTIPROCESSING"] == "1"
  end

  test "snakepit_config merges adapter_env into each pool and allows per-pool overrides" do
    pools = [
      %{name: :pool_a, adapter_env: %{"X" => "pool"}},
      %{name: :pool_b}
    ]

    config =
      ConfigHelper.snakepit_config(
        pools: pools,
        adapter_env: %{"X" => "global", "Y" => "global"}
      )

    [pool_a, pool_b] = Keyword.fetch!(config, :pools)

    assert pool_a.adapter_env["X"] == "pool"
    assert pool_a.adapter_env["Y"] == "global"

    assert pool_b.adapter_env["X"] == "global"
    assert pool_b.adapter_env["Y"] == "global"
  end
end
