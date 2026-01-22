defmodule SnakeBridge.RuntimeContext do
  @moduledoc """
  Process-scoped runtime defaults for SnakeBridge calls.

  Defaults are merged into `__runtime__` options at call time, making it easy to
  set pool/timeout settings once per process or scoped block.
  """

  @context_key :snakebridge_runtime_defaults

  @type defaults :: keyword()

  @doc """
  Sets runtime defaults for the current process.
  """
  @spec put_defaults(defaults() | nil) :: :ok
  def put_defaults(nil), do: clear_defaults()

  def put_defaults(defaults) when is_list(defaults) do
    defaults = normalize_defaults(defaults)

    if defaults == [] do
      clear_defaults()
    else
      Process.put(@context_key, defaults)
      :ok
    end
  end

  @doc """
  Returns runtime defaults for the current process.
  """
  @spec get_defaults() :: defaults()
  def get_defaults do
    Process.get(@context_key, [])
  end

  @doc """
  Clears runtime defaults for the current process.
  """
  @spec clear_defaults() :: :ok
  def clear_defaults do
    Process.delete(@context_key)
    :ok
  end

  @doc """
  Applies runtime defaults for the duration of the given function.
  """
  @spec with_runtime(defaults(), (-> result)) :: result when result: term()
  def with_runtime(opts, fun) when is_list(opts) and is_function(fun, 0) do
    previous = get_defaults()
    merged = merge_defaults(previous, opts)

    put_defaults(merged)

    try do
      fun.()
    after
      if previous == [] do
        clear_defaults()
      else
        Process.put(@context_key, previous)
      end
    end
  end

  defp merge_defaults(current, override) do
    normalize_defaults(List.wrap(current) ++ List.wrap(override))
  end

  defp normalize_defaults(defaults) do
    defaults
    |> List.wrap()
    |> Keyword.new()
  end
end
