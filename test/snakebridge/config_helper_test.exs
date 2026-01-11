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
end
