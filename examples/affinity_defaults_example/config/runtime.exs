import Config

# Single-pool default affinity (no pools list).
SnakeBridge.ConfigHelper.configure_snakepit!(
  pool_size: 2,
  affinity: :strict_queue
)
