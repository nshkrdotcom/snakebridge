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
    original_snakebridge_venv = Application.get_env(:snakebridge, :venv_path)
    original_snakepit_python_packages = Application.get_env(:snakepit, :python_packages)
    original_env = System.get_env("SNAKEBRIDGE_VENV")

    System.delete_env("SNAKEBRIDGE_VENV")
    Application.delete_env(:snakebridge, :venv_path)

    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "snakebridge_config_helper_#{System.unique_integer([:positive])}"
      )

    venv_dir = Path.join(tmp_dir, "venv")
    python_path = Path.join([venv_dir, "bin", "python3"])
    File.mkdir_p!(Path.dirname(python_path))
    File.write!(python_path, "")

    Application.put_env(:snakepit, :python_packages, env_dir: venv_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)

      if is_nil(original_snakepit_python_packages) do
        Application.delete_env(:snakepit, :python_packages)
      else
        Application.put_env(:snakepit, :python_packages, original_snakepit_python_packages)
      end

      if is_nil(original_snakebridge_venv) do
        Application.delete_env(:snakebridge, :venv_path)
      else
        Application.put_env(:snakebridge, :venv_path, original_snakebridge_venv)
      end

      if is_nil(original_env) do
        System.delete_env("SNAKEBRIDGE_VENV")
      else
        System.put_env("SNAKEBRIDGE_VENV", original_env)
      end
    end)

    config = ConfigHelper.snakepit_config()
    assert Keyword.get(config, :python_executable) == python_path
  end
end
