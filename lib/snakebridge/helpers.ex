defmodule SnakeBridge.Helpers do
  @moduledoc """
  Helper registry discovery and configuration for SnakeBridge.
  """

  alias SnakeBridge.{Config, HelperRegistryError}

  @type helper_info :: map()

  @spec discover() :: {:ok, [helper_info()]} | {:error, term()}
  def discover do
    discover(runtime_config())
  end

  @spec discover(Config.t() | map()) :: {:ok, [helper_info()]} | {:error, term()}
  def discover(%Config{} = config) do
    discover(config_to_map(config))
  end

  def discover(%{} = config) do
    payload = payload_config(config, include_adapter_root: true)

    case python_runner().run(helper_index_script(), [Jason.encode!(payload)], runner_opts()) do
      {:ok, output} ->
        parse_output(output)

      {:error, {:python_exit, _status, output}} ->
        {:error, HelperRegistryError.from_python_output(output)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec runtime_config() :: map()
  def runtime_config do
    %{
      helper_paths: Application.get_env(:snakebridge, :helper_paths, ["priv/python/helpers"]),
      helper_pack_enabled: Application.get_env(:snakebridge, :helper_pack_enabled, true),
      helper_allowlist: Application.get_env(:snakebridge, :helper_allowlist, :all),
      inline_enabled: Application.get_env(:snakebridge, :inline_enabled, false)
    }
  end

  @spec enabled?(map()) :: boolean()
  def enabled?(%{} = config) do
    normalized = normalize_config(config)

    normalized.helper_allowlist != [] and
      (normalized.helper_pack_enabled == true or normalized.helper_paths != [])
  end

  @spec payload_config(map(), keyword()) :: map()
  def payload_config(%{} = config, opts \\ []) do
    normalized = normalize_config(config)

    payload = %{
      "helper_paths" => normalized.helper_paths,
      "helper_pack_enabled" => normalized.helper_pack_enabled,
      "helper_allowlist" => allowlist_payload(normalized.helper_allowlist)
    }

    if Keyword.get(opts, :include_adapter_root, false) do
      Map.put(payload, "adapter_root", adapter_root())
    else
      payload
    end
  end

  defp config_to_map(%Config{} = config) do
    %{
      helper_paths: config.helper_paths,
      helper_pack_enabled: config.helper_pack_enabled,
      helper_allowlist: config.helper_allowlist,
      inline_enabled: config.inline_enabled
    }
  end

  defp normalize_config(%{} = config) do
    %{
      helper_paths: normalize_paths(Map.get(config, :helper_paths, ["priv/python/helpers"])),
      helper_pack_enabled: Map.get(config, :helper_pack_enabled, true) == true,
      helper_allowlist: normalize_allowlist(Map.get(config, :helper_allowlist, :all)),
      inline_enabled: Map.get(config, :inline_enabled, false) == true
    }
  end

  defp normalize_paths(paths) do
    paths
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
  end

  defp normalize_allowlist(:all), do: :all
  defp normalize_allowlist("all"), do: :all
  defp normalize_allowlist(nil), do: :all
  defp normalize_allowlist(:none), do: []

  defp normalize_allowlist(list) when is_list(list) do
    list
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
  end

  defp normalize_allowlist(other), do: [to_string(other)]

  defp allowlist_payload(:all), do: "all"
  defp allowlist_payload(list) when is_list(list), do: list

  defp adapter_root do
    :snakebridge
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("python")
  end

  defp python_runner do
    Application.get_env(:snakebridge, :python_runner, SnakeBridge.PythonRunner.System)
  end

  defp runner_opts do
    config = Application.get_env(:snakebridge, :helper_registry, [])
    Keyword.take(config, [:timeout, :env, :cd])
  end

  defp parse_output(output) do
    case Jason.decode(output) do
      {:ok, results} when is_list(results) -> {:ok, results}
      {:ok, %{"error" => error}} -> {:error, error}
      {:error, _} -> {:error, {:json_parse, output}}
    end
  end

  defp helper_index_script do
    ~S"""
    import json
    import sys

    config = json.loads(sys.argv[1])
    adapter_root = config.pop("adapter_root", None)

    if adapter_root:
        sys.path.insert(0, adapter_root)

    from snakebridge_adapter import helper_registry_index

    index = helper_registry_index(config)
    print(json.dumps(index))
    """
  end
end
