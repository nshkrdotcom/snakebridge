defmodule SnakeBridge.SignatureThresholds do
  @moduledoc false

  alias SnakeBridge.SignatureTiers

  @spec enforce!(SnakeBridge.Config.t(), map()) :: :ok | no_return()
  def enforce!(config, manifest) do
    issues =
      config.libraries
      |> Enum.flat_map(&library_issues(&1, config, manifest))

    if issues != [] do
      raise SnakeBridge.CompileError, build_message(issues, config)
    end

    :ok
  end

  defp library_issues(library, config, manifest) do
    strict? =
      case library.strict_signatures do
        nil -> truthy?(config.strict_signatures)
        value -> truthy?(value)
      end

    if strict? do
      min_tier = library.min_signature_tier || config.min_signature_tier
      min_tier = SignatureTiers.normalize(min_tier)

      manifest
      |> symbols_for_library(library)
      |> Enum.reject(fn {_name, source} -> SignatureTiers.meets_min?(source, min_tier) end)
      |> Enum.map(fn {name, source} -> %{name: name, source: source, min: min_tier} end)
    else
      []
    end
  end

  defp symbols_for_library(manifest, library) do
    functions =
      manifest
      |> Map.get("symbols", %{})
      |> Map.values()
      |> Enum.filter(fn info ->
        python_module = info["python_module"] || ""
        String.starts_with?(python_module, library.python_name)
      end)
      |> Enum.map(fn info ->
        name = symbol_name(info["module"], info["name"])
        source = info["signature_source"] || "runtime"
        {name, source}
      end)

    methods =
      manifest
      |> Map.get("classes", %{})
      |> Map.values()
      |> Enum.filter(fn info ->
        python_module = info["python_module"] || ""
        String.starts_with?(python_module, library.python_name)
      end)
      |> Enum.flat_map(&class_methods/1)

    functions ++ methods
  end

  defp class_methods(class_info) do
    module = class_info["module"] || ""

    class_info
    |> Map.get("methods", [])
    |> Enum.map(fn method ->
      name = symbol_name(module, method_name(method))
      source = method["signature_source"] || "runtime"
      {name, source}
    end)
  end

  defp symbol_name(module, name) do
    base = if module in [nil, ""], do: "Unknown", else: module
    suffix = if name in [nil, ""], do: "unknown", else: name
    base <> "." <> suffix
  end

  defp method_name(%{"elixir_name" => name}) when is_binary(name), do: name
  defp method_name(%{elixir_name: name}) when is_binary(name), do: name
  defp method_name(%{"name" => name}) when is_binary(name), do: name
  defp method_name(%{name: name}) when is_binary(name), do: name
  defp method_name(_), do: "unknown"

  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(_), do: true

  defp build_message(issues, config) do
    formatted =
      issues
      |> Enum.map_join("\n", fn %{name: name, source: source, min: min} ->
        "  - #{name} (source: #{source}, min: #{min})"
      end)

    min_tier = SignatureTiers.normalize(config.min_signature_tier)

    """
    Strict signature mode: #{length(issues)} symbol(s) below minimum signature tier #{min_tier}.

    Offenders:
    #{formatted}

    To fix:
      1. Enable stubs or stubgen for better signatures
      2. Lower the configured min_signature_tier
      3. Disable strict_signatures for this library
    """
  end
end
