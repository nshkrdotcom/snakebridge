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

    added =
      for key <- new_keys -- old_keys,
          do: {:added, path ++ [normalize_key(key)], Map.get(new, key)}

    removed =
      for key <- old_keys -- new_keys,
          do: {:removed, path ++ [normalize_key(key)], Map.get(old, key)}

    # For keys that exist in both, check if they're modified
    modified =
      for key <- old_keys -- (old_keys -- new_keys),
          old_val = Map.get(old, key),
          new_val = Map.get(new, key),
          old_val != new_val do
        # Only recurse one level deep (into containers like "classes", "functions")
        # Don't recurse into entity descriptors
        if length(path) < 1 and is_map(old_val) and is_map(new_val) do
          diff_maps(old_val, new_val, path ++ [normalize_key(key)])
        else
          [{:modified, path ++ [normalize_key(key)], old_val, new_val}]
        end
      end
      |> List.flatten()

    added ++ removed ++ modified
  end

  # Only recurse into maps that look like containers (not entities)
  # A container has mostly the same keys in old and new
  # An entity replacement has different keys
  defp should_recurse?(old_val, new_val) do
    if is_map(old_val) and is_map(new_val) and map_size(old_val) > 0 and
         map_size(new_val) > 0 do
      old_keys = MapSet.new(Map.keys(old_val))
      new_keys = MapSet.new(Map.keys(new_val))
      common_keys = MapSet.intersection(old_keys, new_keys)

      # If more than 50% of keys are common, treat as container and recurse
      # Otherwise, treat as entity replacement
      common_count = MapSet.size(common_keys)
      total_keys = max(MapSet.size(old_keys), MapSet.size(new_keys))

      common_count / total_keys > 0.5
    else
      false
    end
  end

  # Convert all keys to strings for consistent path representation
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)

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
