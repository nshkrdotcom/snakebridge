import Config

# Auto-configure snakepit for snakebridge with affinity modes per pool.
SnakeBridge.ConfigHelper.configure_snakepit!(
  pools: [
    %{name: :hint_pool, pool_size: 2, affinity: :hint},
    %{name: :strict_queue_pool, pool_size: 2, affinity: :strict_queue},
    %{name: :strict_fail_fast_pool, pool_size: 2, affinity: :strict_fail_fast}
  ]
)
