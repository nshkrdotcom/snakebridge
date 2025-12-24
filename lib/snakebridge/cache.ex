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
  Store configuration to both ETS and filesystem.

  Returns `{:ok, file_path}` where file_path is the location of the cached file.
  """
  @spec store(SnakeBridge.Config.t()) :: {:ok, String.t()}
  def store(%SnakeBridge.Config{} = config) do
    hash = SnakeBridge.Config.hash(config)
    :ets.insert(:snakebridge_cache, {hash, config, System.system_time(:second)})

    # Also persist to filesystem
    cache_dir = get_cache_dir()
    File.mkdir_p!(cache_dir)

    cache_path = Path.join(cache_dir, hash)
    serialized = :erlang.term_to_binary(config)
    File.write!(cache_path, serialized)

    {:ok, cache_path}
  end

  @doc """
  Load configuration from cache (tries ETS first, then filesystem).
  """
  @spec load(String.t()) :: {:ok, SnakeBridge.Config.t()} | {:error, :not_found}
  def load(cache_path_or_hash) do
    # If it's a full path, extract the hash
    hash =
      if String.contains?(cache_path_or_hash, "/") do
        Path.basename(cache_path_or_hash)
      else
        cache_path_or_hash
      end

    # Try ETS first
    case :ets.lookup(:snakebridge_cache, hash) do
      [{^hash, config, _timestamp}] ->
        {:ok, config}

      [] ->
        # Try filesystem
        load_from_file(cache_path_or_hash)
    end
  end

  defp load_from_file(cache_path) do
    if File.exists?(cache_path) do
      with {:ok, contents} <- File.read(cache_path) do
        {:ok, :erlang.binary_to_term(contents, [:safe])}
      end
    else
      {:error, :not_found}
    end
  end

  defp get_cache_dir do
    Application.get_env(
      :snakebridge,
      :cache_path,
      Path.join(System.tmp_dir!(), "snakebridge")
    )
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
