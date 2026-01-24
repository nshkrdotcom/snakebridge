defmodule SnakeBridge.CacheOwner do
  @moduledoc false

  use GenServer

  @tables [
    {:snakebridge_docs,
     [:set, :public, :named_table, read_concurrency: true, write_concurrency: true]},
    {:snakebridge_exception_cache, [:set, :public, :named_table, read_concurrency: true]}
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    Enum.each(@tables, fn {name, opts} -> ensure_table(name, opts) end)
    {:ok, %{}}
  end

  defp ensure_table(name, opts) do
    case :ets.whereis(name) do
      :undefined -> :ets.new(name, opts)
      _ -> name
    end
  end
end
