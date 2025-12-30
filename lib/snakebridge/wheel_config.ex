defmodule SnakeBridge.WheelConfig do
  @moduledoc """
  Configuration-based wheel variant selection.
  """

  @default_config_path Path.join(["config", "wheel_variants.json"])

  @doc """
  Loads wheel configuration from file or uses defaults.
  """
  @spec load_config() :: map()
  def load_config do
    case File.read(config_path()) do
      {:ok, content} ->
        Jason.decode!(content)

      {:error, _} ->
        default_config()
    end
  end

  @doc """
  Gets available variants for a package.
  """
  @spec get_variants(String.t()) :: [String.t()]
  def get_variants(package) do
    config = load_config()
    get_in(config, ["packages", package, "variants"]) || ["cpu"]
  end

  @doc """
  Returns the configured packages that define variants.
  """
  @spec packages() :: [String.t()]
  def packages do
    config = load_config()

    config
    |> Map.get("packages", %{})
    |> Map.keys()
  end

  @doc """
  Gets CUDA mapping for a version string.
  """
  @spec get_cuda_mapping(String.t() | nil) :: String.t() | nil
  def get_cuda_mapping(nil), do: nil

  def get_cuda_mapping(version) do
    config = load_config()

    Map.get(config["cuda_mappings"] || %{}, version) ||
      Map.get(config["cuda_mappings"] || %{}, normalize_cuda_version(version))
  end

  @doc """
  Returns the configured ROCm variant, if any.
  """
  @spec rocm_variant() :: String.t() | nil
  def rocm_variant do
    config = load_config()
    config["rocm_variant"]
  end

  @doc false
  def config_path do
    Application.get_env(:snakebridge, :wheel_config_path) ||
      Path.join(File.cwd!(), @default_config_path)
  end

  defp default_config do
    %{
      "packages" => %{
        "torch" => %{"variants" => ["cpu", "cu118", "cu121", "cu124", "rocm5.7"]},
        "torchvision" => %{"variants" => ["cpu", "cu118", "cu121", "cu124", "rocm5.7"]},
        "torchaudio" => %{"variants" => ["cpu", "cu118", "cu121", "cu124", "rocm5.7"]}
      },
      "cuda_mappings" => %{
        "11.7" => "cu118",
        "11.8" => "cu118",
        "12.0" => "cu121",
        "12.1" => "cu121",
        "12.2" => "cu121",
        "12.3" => "cu124",
        "12.4" => "cu124",
        "12.5" => "cu124"
      },
      "rocm_variant" => "rocm5.7"
    }
  end

  defp normalize_cuda_version(version) when is_binary(version) do
    version
    |> String.split(".")
    |> Enum.take(2)
    |> Enum.join()
  end

  defp normalize_cuda_version(_), do: nil
end
