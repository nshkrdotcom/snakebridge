defmodule SnakeBridge.Manifest.Diff do
  @moduledoc """
  Diff a manifest config against live Python introspection.
  """

  @type diff_result :: %{
          manifest_count: non_neg_integer(),
          schema_count: non_neg_integer(),
          missing_in_schema: [String.t()],
          new_in_schema: [String.t()],
          common: [String.t()]
        }

  @spec diff(SnakeBridge.Config.t(), map()) :: diff_result()
  def diff(%SnakeBridge.Config{} = config, schema) when is_map(schema) do
    manifest_names =
      config.functions
      |> Enum.map(&get_name/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    schema_names =
      schema
      |> Map.get("functions", %{})
      |> Map.keys()
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    missing_in_schema = MapSet.difference(manifest_names, schema_names) |> MapSet.to_list()
    new_in_schema = MapSet.difference(schema_names, manifest_names) |> MapSet.to_list()
    common = MapSet.intersection(manifest_names, schema_names) |> MapSet.to_list()

    %{
      manifest_count: MapSet.size(manifest_names),
      schema_count: MapSet.size(schema_names),
      missing_in_schema: Enum.sort(missing_in_schema),
      new_in_schema: Enum.sort(new_in_schema),
      common: Enum.sort(common)
    }
  end

  defp get_name(func) when is_map(func) do
    Map.get(func, :name) || Map.get(func, "name")
  end
end
