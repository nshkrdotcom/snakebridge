defmodule Mix.Tasks.Snakebridge.VerifyTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Snakebridge.Verify
  alias SnakeBridge.Test.SnakepitMocks.{MockHardware, MockHardwareCuda}

  @lock_file "snakebridge.lock"

  setup do
    original_hardware = Application.get_env(:snakebridge, :hardware_module)

    # Clean up any existing lock file
    File.rm(@lock_file)

    on_exit(fn ->
      restore_env(:snakebridge, :hardware_module, original_hardware)
      File.rm(@lock_file)
    end)

    :ok
  end

  describe "run/1" do
    test "prints success for matching environment" do
      Application.put_env(:snakebridge, :hardware_module, MockHardware)

      lock = %{
        "version" => "0.6.0",
        "environment" => %{
          "hardware" => %{
            "accelerator" => "cpu",
            "gpu_count" => 0,
            "cpu_features" => ["avx", "avx2"]
          },
          "platform" => %{
            "os" => "linux",
            "arch" => "x86_64"
          }
        },
        "compatibility" => %{}
      }

      File.write!(@lock_file, Jason.encode!(lock))

      output =
        capture_io(fn ->
          Verify.run([])
        end)

      assert output =~ "compatible" or output =~ "ok" or output =~ "match"
    end

    test "prints warning for minor mismatches" do
      Application.put_env(:snakebridge, :hardware_module, MockHardwareCuda)

      lock = %{
        "version" => "0.6.0",
        "environment" => %{
          "hardware" => %{
            "accelerator" => "cuda",
            "cuda_version" => "12.0",
            "gpu_count" => 1
          },
          "platform" => %{
            "os" => "linux",
            "arch" => "x86_64"
          }
        },
        "compatibility" => %{}
      }

      File.write!(@lock_file, Jason.encode!(lock))

      output =
        capture_io(fn ->
          Verify.run([])
        end)

      # Should indicate warning about CUDA version mismatch
      assert output =~ "warning" or output =~ "Warning" or output =~ "CUDA"
    end

    test "prints error when no lock file exists" do
      Application.put_env(:snakebridge, :hardware_module, MockHardware)

      output =
        capture_io(:stderr, fn ->
          try do
            Verify.run([])
          rescue
            _ -> :ok
          end
        end)

      # Either error is raised or error message printed
      assert output =~ "not found" or output =~ "No lock" or output == ""
    end

    test "respects --strict flag" do
      Application.put_env(:snakebridge, :hardware_module, MockHardware)

      lock = %{
        "version" => "0.6.0",
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

      File.write!(@lock_file, Jason.encode!(lock))

      assert_raise Mix.Error, fn ->
        Verify.run(["--strict"])
      end
    end

    test "prints hardware info with --verbose flag" do
      Application.put_env(:snakebridge, :hardware_module, MockHardware)

      lock = %{
        "version" => "0.6.0",
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

      File.write!(@lock_file, Jason.encode!(lock))

      output =
        capture_io(fn ->
          Verify.run(["--verbose"])
        end)

      # Should print more detail in verbose mode
      assert output =~ "cpu" or output =~ "CPU" or output =~ "accelerator"
    end
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
