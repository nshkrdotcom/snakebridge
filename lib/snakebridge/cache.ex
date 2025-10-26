defmodule SnakeBridge.Cache do
  @moduledoc """
  Schema cache with ETS backend.
  """

  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(:snakebridge_cache, [:named_table, :public, :set])
    {:ok, %{}}
  end

  @doc """
  Store configuration.
  """
  @spec store(SnakeBridge.Config.t()) :: {:ok, String.t()}
  def store(%SnakeBridge.Config{} = config) do
    hash = SnakeBridge.Config.hash(config)
    :ets.insert(:snakebridge_cache, {hash, config, System.system_time(:second)})
    {:ok, hash}
  end

  @doc """
  Load configuration from cache.
  """
  @spec load(String.t()) :: {:ok, SnakeBridge.Config.t()} | {:error, :not_found}
  def load(hash) do
    case :ets.lookup(:snakebridge_cache, hash) do
      [{^hash, config, _timestamp}] -> {:ok, config}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Clear all caches.
  """
  @spec clear_all() :: :ok
  def clear_all do
    :ets.delete_all_objects(:snakebridge_cache)
    :ok
  end
end
