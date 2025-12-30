defmodule SnakeBridge.WheelSelector do
  @moduledoc """
  Selects the appropriate wheel variant for Python packages based on hardware.

  PyTorch and related packages (torchvision, torchaudio) have different wheel
  variants for different hardware configurations:

  - `cpu` - CPU-only build
  - `cu118` - CUDA 11.8
  - `cu121` - CUDA 12.1
  - `cu124` - CUDA 12.4
  - `rocm5.7` - AMD ROCm 5.7

  This module detects the current hardware and selects the appropriate variant.

  ## Examples

      # Get the PyTorch variant for current hardware
      variant = SnakeBridge.WheelSelector.pytorch_variant()
      #=> "cu121" or "cpu"

      # Get the index URL for pip
      url = SnakeBridge.WheelSelector.pytorch_index_url()
      #=> "https://download.pytorch.org/whl/cu121"

      # Generate pip install command
      cmd = SnakeBridge.WheelSelector.pip_install_command("torch", "2.1.0")
      #=> "pip install torch==2.1.0 --index-url https://download.pytorch.org/whl/cu121"

  """

  @type wheel_info :: %{
          package: String.t(),
          version: String.t(),
          variant: String.t() | nil,
          index_url: String.t() | nil
        }

  @doc """
  Returns the PyTorch wheel variant for the current hardware.

  ## Examples

      SnakeBridge.WheelSelector.pytorch_variant()
      #=> "cu121"  # On CUDA 12.1 system
      #=> "cpu"    # On CPU-only system

  """
  @spec pytorch_variant() :: String.t()
  def pytorch_variant do
    caps = hardware_module().capabilities()
    strategy_module().variant_for("torch", caps) || "cpu"
  end

  @doc """
  Returns the PyTorch index URL for pip based on current hardware.

  ## Examples

      SnakeBridge.WheelSelector.pytorch_index_url()
      #=> "https://download.pytorch.org/whl/cu121"

  """
  @spec pytorch_index_url() :: String.t()
  def pytorch_index_url do
    strategy_module().index_url_for_variant(pytorch_variant())
  end

  @doc """
  Generates a pip install command for a package.

  For PyTorch packages (torch, torchvision, torchaudio), includes the
  appropriate --index-url for hardware-specific wheels.

  ## Examples

      SnakeBridge.WheelSelector.pip_install_command("torch", "2.1.0")
      #=> "pip install torch==2.1.0 --index-url https://download.pytorch.org/whl/cu121"

      SnakeBridge.WheelSelector.pip_install_command("numpy", "1.26.4")
      #=> "pip install numpy==1.26.4"

  """
  @spec pip_install_command(String.t(), String.t()) :: String.t()
  def pip_install_command(package, version) do
    base = "pip install #{package}==#{version}"
    wheel_info = select_wheel(package, version)

    if wheel_info.index_url do
      "#{base} --index-url #{wheel_info.index_url}"
    else
      base
    end
  end

  @doc """
  Normalizes a CUDA version string for wheel naming.

  ## Examples

      SnakeBridge.WheelSelector.normalize_cuda_version("12.1")
      #=> "121"

      SnakeBridge.WheelSelector.normalize_cuda_version("11.8")
      #=> "118"

  """
  @spec normalize_cuda_version(String.t() | nil) :: String.t() | nil
  def normalize_cuda_version(nil), do: nil

  def normalize_cuda_version(version) when is_binary(version) do
    version
    |> String.split(".")
    |> Enum.take(2)
    |> Enum.join()
  end

  @doc """
  Selects the appropriate wheel for a package based on current hardware.

  Returns wheel info including variant and index URL if applicable.

  ## Examples

      SnakeBridge.WheelSelector.select_wheel("torch", "2.1.0")
      #=> %{package: "torch", version: "2.1.0", variant: "cu121", index_url: "..."}

      SnakeBridge.WheelSelector.select_wheel("numpy", "1.26.4")
      #=> %{package: "numpy", version: "1.26.4", variant: nil, index_url: nil}

  """
  @spec select_wheel(String.t(), String.t()) :: wheel_info()
  def select_wheel(package, version) do
    strategy_module().select_wheel(package, version, hardware_module().capabilities())
  end

  @doc """
  Checks if a package is a PyTorch package that needs hardware-specific wheels.
  """
  @spec pytorch_package?(String.t()) :: boolean()
  def pytorch_package?(package) do
    package in SnakeBridge.WheelConfig.packages()
  end

  @doc """
  Returns all available PyTorch variants for the given CUDA versions.

  Useful for generating lock files that support multiple hardware configurations.
  """
  @spec available_variants() :: [String.t()]
  def available_variants do
    available_variants("torch")
  end

  @spec available_variants(String.t()) :: [String.t()]
  def available_variants(package) do
    strategy_module().available_variants(package)
  end

  @doc """
  Returns the best matching CUDA variant for a given CUDA version.

  Falls back to the closest available version.

  ## Examples

      SnakeBridge.WheelSelector.best_cuda_variant("12.3")
      #=> "cu124"

      SnakeBridge.WheelSelector.best_cuda_variant("12.1")
      #=> "cu121"

  """

  @spec best_cuda_variant(String.t() | nil) :: String.t()
  def best_cuda_variant(cuda_version) do
    strategy_module().best_cuda_variant(cuda_version)
  end

  # Private functions

  defp hardware_module do
    Application.get_env(:snakebridge, :hardware_module, Snakepit.Hardware)
  end

  defp strategy_module do
    Application.get_env(:snakebridge, :wheel_strategy, SnakeBridge.WheelSelector.ConfigStrategy)
  end
end
