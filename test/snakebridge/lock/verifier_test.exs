defmodule SnakeBridge.Lock.VerifierTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.Lock.Verifier
  alias SnakeBridge.Test.SnakepitMocks.{MockHardware, MockHardwareCuda}

  setup do
    original_hardware = Application.get_env(:snakebridge, :hardware_module)

    on_exit(fn ->
      restore_env(:snakebridge, :hardware_module, original_hardware)
    end)

    :ok
  end

  describe "verify/1" do
    test "returns :ok for matching environment (CPU)" do
      Application.put_env(:snakebridge, :hardware_module, MockHardware)

      lock = %{
        "environment" => %{
          "hardware" => %{
            "accelerator" => "cpu",
            "cuda_version" => nil,
            "gpu_count" => 0,
            "cpu_features" => ["avx", "avx2"]
          },
          "platform" => %{
            "os" => "linux",
            "arch" => "x86_64"
          },
          "python_version" => "3.12.0"
        },
        "compatibility" => %{
          "cuda_min" => nil,
          "compute_capability_min" => nil
        }
      }

      assert :ok = Verifier.verify(lock)
    end

    test "returns :ok for matching CUDA environment" do
      Application.put_env(:snakebridge, :hardware_module, MockHardwareCuda)

      lock = %{
        "environment" => %{
          "hardware" => %{
            "accelerator" => "cuda",
            "cuda_version" => "12.1",
            "gpu_count" => 2,
            "cpu_features" => ["avx", "avx2"]
          },
          "platform" => %{
            "os" => "linux",
            "arch" => "x86_64"
          },
          "python_version" => "3.12.0"
        },
        "compatibility" => %{
          "cuda_min" => "12.0",
          "compute_capability_min" => "8.0"
        }
      }

      assert :ok = Verifier.verify(lock)
    end

    test "returns warning when CUDA version differs within major version" do
      Application.put_env(:snakebridge, :hardware_module, MockHardwareCuda)

      lock = %{
        "environment" => %{
          "hardware" => %{
            "accelerator" => "cuda",
            "cuda_version" => "12.0",
            "gpu_count" => 2
          },
          "platform" => %{
            "os" => "linux",
            "arch" => "x86_64"
          }
        },
        "compatibility" => %{}
      }

      result = Verifier.verify(lock)
      assert {:warning, warnings} = result
      assert Enum.any?(warnings, &String.contains?(&1, "CUDA version"))
    end

    test "returns error when lock requires CUDA but current has none" do
      Application.put_env(:snakebridge, :hardware_module, MockHardware)

      lock = %{
        "environment" => %{
          "hardware" => %{
            "accelerator" => "cuda",
            "cuda_version" => "12.1",
            "gpu_count" => 2
          },
          "platform" => %{
            "os" => "linux",
            "arch" => "x86_64"
          }
        },
        "compatibility" => %{}
      }

      result = Verifier.verify(lock)
      assert {:error, errors} = result
      assert Enum.any?(errors, &String.contains?(&1, "CUDA"))
    end

    test "returns error when platform OS differs" do
      Application.put_env(:snakebridge, :hardware_module, MockHardware)

      lock = %{
        "environment" => %{
          "hardware" => %{
            "accelerator" => "cpu"
          },
          "platform" => %{
            "os" => "windows",
            "arch" => "x86_64"
          }
        },
        "compatibility" => %{}
      }

      result = Verifier.verify(lock)
      assert {:error, errors} = result
      assert Enum.any?(errors, &String.contains?(&1, "Platform mismatch"))
    end

    test "returns error when architecture differs" do
      Application.put_env(:snakebridge, :hardware_module, MockHardware)

      lock = %{
        "environment" => %{
          "hardware" => %{
            "accelerator" => "cpu"
          },
          "platform" => %{
            "os" => "linux",
            "arch" => "arm64"
          }
        },
        "compatibility" => %{}
      }

      result = Verifier.verify(lock)
      assert {:error, errors} = result
      assert Enum.any?(errors, &String.contains?(&1, "Architecture mismatch"))
    end

    test "returns warning when accelerator downgrades from CUDA to CPU" do
      Application.put_env(:snakebridge, :hardware_module, MockHardware)

      lock = %{
        "environment" => %{
          "hardware" => %{
            "accelerator" => "cuda",
            "cuda_version" => nil
          },
          "platform" => %{
            "os" => "linux",
            "arch" => "x86_64"
          }
        },
        "compatibility" => %{}
      }

      result = Verifier.verify(lock)
      # Should be warning or error, since CUDA is required but not available
      assert match?({:warning, _}, result) or match?({:error, _}, result)
    end

    test "handles missing hardware section gracefully" do
      Application.put_env(:snakebridge, :hardware_module, MockHardware)

      lock = %{
        "environment" => %{
          "platform" => %{
            "os" => "linux",
            "arch" => "x86_64"
          }
        },
        "compatibility" => %{}
      }

      result = Verifier.verify(lock)
      # Should handle missing hardware gracefully
      assert result == :ok or match?({:warning, _}, result)
    end

    test "handles nil lock gracefully" do
      Application.put_env(:snakebridge, :hardware_module, MockHardware)

      result = Verifier.verify(nil)
      assert {:error, ["No lock file provided"]} = result
    end

    test "handles empty lock gracefully" do
      Application.put_env(:snakebridge, :hardware_module, MockHardware)

      result = Verifier.verify(%{})
      # Should handle empty lock with warning or ok
      assert result == :ok or match?({:warning, _}, result)
    end
  end

  describe "verify!/1" do
    test "raises on error" do
      Application.put_env(:snakebridge, :hardware_module, MockHardware)

      lock = %{
        "environment" => %{
          "hardware" => %{
            "accelerator" => "cuda",
            "cuda_version" => "12.1"
          },
          "platform" => %{
            "os" => "linux",
            "arch" => "x86_64"
          }
        },
        "compatibility" => %{}
      }

      assert_raise SnakeBridge.EnvironmentError, fn ->
        Verifier.verify!(lock)
      end
    end

    test "returns :ok on success" do
      Application.put_env(:snakebridge, :hardware_module, MockHardware)

      lock = %{
        "environment" => %{
          "hardware" => %{
            "accelerator" => "cpu"
          },
          "platform" => %{
            "os" => "linux",
            "arch" => "x86_64"
          }
        },
        "compatibility" => %{}
      }

      assert :ok = Verifier.verify!(lock)
    end
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
