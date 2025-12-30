defmodule SnakeBridge.WheelSelector.ConfigStrategy do
  @moduledoc false

  alias SnakeBridge.WheelConfig

  @type wheel_info :: %{
          package: String.t(),
          version: String.t(),
          variant: String.t() | nil,
          index_url: String.t() | nil
        }

  @spec select_wheel(String.t(), String.t(), map()) :: wheel_info()
  def select_wheel(package, version, caps) do
    variant = variant_for(package, caps)

    %{
      package: package,
      version: version,
      variant: variant,
      index_url: index_url_for_variant(variant)
    }
  end

  @spec variant_for(String.t(), map()) :: String.t() | nil
  def variant_for(package, caps) do
    if variant_package?(package) do
      variants = WheelConfig.get_variants(package)

      cond do
        caps.cuda and caps.cuda_version ->
          pick_variant(best_cuda_variant(caps.cuda_version), variants)

        caps.rocm ->
          rocm_variant = WheelConfig.rocm_variant()
          pick_variant(rocm_variant, variants)

        true ->
          pick_variant("cpu", variants)
      end
    else
      nil
    end
  end

  @spec available_variants(String.t()) :: [String.t()]
  def available_variants(package) do
    if variant_package?(package) do
      WheelConfig.get_variants(package)
    else
      []
    end
  end

  @spec best_cuda_variant(String.t() | nil) :: String.t()
  def best_cuda_variant(nil), do: "cpu"

  def best_cuda_variant(cuda_version) do
    WheelConfig.get_cuda_mapping(cuda_version) || cuda_variant_fallback(cuda_version)
  end

  @spec index_url_for_variant(String.t() | nil) :: String.t() | nil
  def index_url_for_variant(nil), do: nil

  def index_url_for_variant(variant) do
    "https://download.pytorch.org/whl/#{variant}"
  end

  defp variant_package?(package) do
    package in WheelConfig.packages()
  end

  defp pick_variant(nil, variants) do
    pick_variant("cpu", variants)
  end

  defp pick_variant(preferred, variants) do
    cond do
      preferred in variants ->
        preferred

      "cpu" in variants ->
        "cpu"

      variants == [] ->
        nil

      true ->
        List.first(variants)
    end
  end

  defp cuda_variant_fallback(version) do
    normalized = normalize_cuda_version(version)

    case Integer.parse(normalized || "") do
      {value, _} when value >= 124 -> "cu124"
      {value, _} when value >= 120 -> "cu121"
      {value, _} when value >= 117 -> "cu118"
      _ -> "cpu"
    end
  end

  defp normalize_cuda_version(version) when is_binary(version) do
    version
    |> String.split(".")
    |> Enum.take(2)
    |> Enum.join()
  end

  defp normalize_cuda_version(_), do: nil
end
