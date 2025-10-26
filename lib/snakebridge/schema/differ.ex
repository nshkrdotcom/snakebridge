defmodule SnakeBridge.Schema.Differ do
  @moduledoc """
  Computes diffs between schema versions (Git-style).
  """

  @doc """
  Compute diff between two schemas.
  """
  @spec diff(map(), map()) :: list()
  def diff(old_schema, new_schema) when is_map(old_schema) and is_map(new_schema) do
    diff_maps(old_schema, new_schema, [])
  end

  defp diff_maps(old, new, path) do
    old_keys = Map.keys(old)
    new_keys = Map.keys(new)

    added = for key <- new_keys -- old_keys, do: {:added, path ++ [key], Map.get(new, key)}
    removed = for key <- old_keys -- new_keys, do: {:removed, path ++ [key], Map.get(old, key)}

    modified =
      for key <- old_keys -- (old_keys -- new_keys),
          old_val = Map.get(old, key),
          new_val = Map.get(new, key),
          old_val != new_val do
        {:modified, path ++ [key], old_val, new_val}
      end

    added ++ removed ++ modified
  end

  @doc """
  Generate human-readable diff summary.
  """
  @spec diff_summary(list()) :: String.t()
  def diff_summary(changes) do
    added = Enum.count(changes, &match?({:added, _, _}, &1))
    removed = Enum.count(changes, &match?({:removed, _, _}, &1))
    modified = Enum.count(changes, &match?({:modified, _, _, _}, &1))

    """
    Added: #{added}
    Removed: #{removed}
    Modified: #{modified}
    """
  end
end
