defmodule SnakeBridge.Test.SnakepitMocks do
  @moduledoc """
  Mock modules for Snakepit dependencies during testing.
  """

  defmodule MockHardware do
    @moduledoc """
    Mock implementation of Snakepit.Hardware for testing.
    """

    @default_identity %{
      "platform" => "linux-x86_64",
      "accelerator" => "cpu",
      "cpu_features" => ["avx", "avx2"],
      "gpu_count" => 0
    }

    @default_capabilities %{
      cuda: false,
      cuda_version: nil,
      cudnn: false,
      cudnn_version: nil,
      mps: false,
      rocm: false,
      avx: true,
      avx2: true,
      avx512: false
    }

    def identity do
      case Process.get(:mock_hardware_identity) do
        nil -> @default_identity
        custom -> custom
      end
    end

    def capabilities do
      case Process.get(:mock_hardware_capabilities) do
        nil -> @default_capabilities
        custom -> custom
      end
    end

    def detect do
      %{
        accelerator: String.to_atom(identity()["accelerator"]),
        platform: identity()["platform"],
        cpu: %{
          cores: 8,
          threads: 16,
          model: "Test CPU",
          features: Enum.map(identity()["cpu_features"], &String.to_atom/1),
          memory_total_mb: 32_768
        },
        cuda: nil,
        mps: nil,
        rocm: nil
      }
    end

    def select(:auto), do: {:ok, :cpu}
    def select(:cpu), do: {:ok, :cpu}
    def select(:cuda), do: {:error, :device_not_available}
    def select(:mps), do: {:error, :device_not_available}

    def clear_cache, do: :ok

    # Test helper to set mock identity
    def set_identity(identity), do: Process.put(:mock_hardware_identity, identity)
    def reset_identity, do: Process.delete(:mock_hardware_identity)
  end

  defmodule MockHardwareCuda do
    @moduledoc """
    Mock implementation of Snakepit.Hardware with CUDA available.
    """

    def identity do
      %{
        "platform" => "linux-x86_64",
        "accelerator" => "cuda",
        "cpu_features" => ["avx", "avx2", "avx512f"],
        "gpu_count" => 2,
        "cuda_version" => "12.1",
        "cudnn_version" => "8.9.0",
        "gpu_compute_capability" => ["8.6", "8.6"]
      }
    end

    def capabilities do
      %{
        cuda: true,
        cuda_version: "12.1",
        cudnn: true,
        cudnn_version: "8.9.0",
        mps: false,
        rocm: false,
        avx: true,
        avx2: true,
        avx512: true
      }
    end

    def detect do
      %{
        accelerator: :cuda,
        platform: "linux-x86_64",
        cpu: %{
          cores: 16,
          threads: 32,
          model: "AMD EPYC 7742",
          features: [:avx, :avx2, :avx512f],
          memory_total_mb: 131_072
        },
        cuda: %{
          version: "12.1",
          driver_version: "535.86.10",
          cudnn_version: "8.9.0",
          devices: [
            %{
              id: 0,
              name: "NVIDIA A100-SXM4-80GB",
              memory_total_mb: 81_920,
              compute_capability: "8.0"
            },
            %{
              id: 1,
              name: "NVIDIA A100-SXM4-80GB",
              memory_total_mb: 81_920,
              compute_capability: "8.0"
            }
          ]
        },
        mps: nil,
        rocm: nil
      }
    end

    def select(:auto), do: {:ok, {:cuda, 0}}
    def select(:cpu), do: {:ok, :cpu}
    def select(:cuda), do: {:ok, {:cuda, 0}}
    def select({:cuda, id}), do: {:ok, {:cuda, id}}
    def select(:mps), do: {:error, :device_not_available}

    def clear_cache, do: :ok
  end

  defmodule MockHardwareMps do
    @moduledoc """
    Mock implementation of Snakepit.Hardware with Apple MPS available.
    """

    def identity do
      %{
        "platform" => "macos-arm64",
        "accelerator" => "mps",
        "cpu_features" => [],
        "gpu_count" => 1
      }
    end

    def capabilities do
      %{
        cuda: false,
        cuda_version: nil,
        cudnn: false,
        cudnn_version: nil,
        mps: true,
        rocm: false,
        avx: false,
        avx2: false,
        avx512: false
      }
    end

    def detect do
      %{
        accelerator: :mps,
        platform: "macos-arm64",
        cpu: %{
          cores: 10,
          threads: 10,
          model: "Apple M2 Pro",
          features: [],
          memory_total_mb: 32_768
        },
        cuda: nil,
        mps: %{available: true, device_name: "Apple M2 Pro", memory_total_mb: 32_768},
        rocm: nil
      }
    end

    def select(:auto), do: {:ok, :mps}
    def select(:cpu), do: {:ok, :cpu}
    def select(:cuda), do: {:error, :device_not_available}
    def select(:mps), do: {:ok, :mps}

    def clear_cache, do: :ok
  end
end
