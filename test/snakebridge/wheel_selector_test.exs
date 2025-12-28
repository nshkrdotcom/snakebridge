defmodule SnakeBridge.WheelSelectorTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.Test.SnakepitMocks.{MockHardware, MockHardwareCuda, MockHardwareMps}
  alias SnakeBridge.WheelSelector

  setup do
    original_hardware = Application.get_env(:snakebridge, :hardware_module)

    on_exit(fn ->
      restore_env(:snakebridge, :hardware_module, original_hardware)
    end)

    :ok
  end

  describe "pytorch_variant/0" do
    test "returns 'cpu' when no CUDA available" do
      Application.put_env(:snakebridge, :hardware_module, MockHardware)
      assert WheelSelector.pytorch_variant() == "cpu"
    end

    test "returns CUDA variant when CUDA available" do
      Application.put_env(:snakebridge, :hardware_module, MockHardwareCuda)
      assert WheelSelector.pytorch_variant() == "cu121"
    end

    test "returns 'cpu' for MPS (same wheel used)" do
      Application.put_env(:snakebridge, :hardware_module, MockHardwareMps)
      assert WheelSelector.pytorch_variant() == "cpu"
    end
  end

  describe "pytorch_index_url/0" do
    test "returns CPU wheel URL when no CUDA" do
      Application.put_env(:snakebridge, :hardware_module, MockHardware)
      assert WheelSelector.pytorch_index_url() == "https://download.pytorch.org/whl/cpu"
    end

    test "returns CUDA wheel URL when CUDA available" do
      Application.put_env(:snakebridge, :hardware_module, MockHardwareCuda)
      assert WheelSelector.pytorch_index_url() == "https://download.pytorch.org/whl/cu121"
    end

    test "returns CPU wheel URL for MPS" do
      Application.put_env(:snakebridge, :hardware_module, MockHardwareMps)
      assert WheelSelector.pytorch_index_url() == "https://download.pytorch.org/whl/cpu"
    end
  end

  describe "pip_install_command/2" do
    test "generates torch install with index URL for CUDA" do
      Application.put_env(:snakebridge, :hardware_module, MockHardwareCuda)

      cmd = WheelSelector.pip_install_command("torch", "2.1.0")
      assert cmd =~ "pip install torch==2.1.0"
      assert cmd =~ "--index-url"
      assert cmd =~ "cu121"
    end

    test "generates torch install with CPU index" do
      Application.put_env(:snakebridge, :hardware_module, MockHardware)

      cmd = WheelSelector.pip_install_command("torch", "2.1.0")
      assert cmd =~ "pip install torch==2.1.0"
      assert cmd =~ "--index-url"
      assert cmd =~ "cpu"
    end

    test "generates standard pip install for non-torch packages" do
      Application.put_env(:snakebridge, :hardware_module, MockHardwareCuda)

      cmd = WheelSelector.pip_install_command("numpy", "1.26.4")
      assert cmd == "pip install numpy==1.26.4"
      refute cmd =~ "--index-url"
    end

    test "handles torchvision with index URL" do
      Application.put_env(:snakebridge, :hardware_module, MockHardwareCuda)

      cmd = WheelSelector.pip_install_command("torchvision", "0.16.0")
      assert cmd =~ "--index-url"
      assert cmd =~ "cu121"
    end

    test "handles torchaudio with index URL" do
      Application.put_env(:snakebridge, :hardware_module, MockHardwareCuda)

      cmd = WheelSelector.pip_install_command("torchaudio", "2.1.0")
      assert cmd =~ "--index-url"
      assert cmd =~ "cu121"
    end
  end

  describe "normalize_cuda_version/1" do
    test "normalizes 12.1 to cu121" do
      assert WheelSelector.normalize_cuda_version("12.1") == "121"
    end

    test "normalizes 11.8 to cu118" do
      assert WheelSelector.normalize_cuda_version("11.8") == "118"
    end

    test "normalizes 12.4 to cu124" do
      assert WheelSelector.normalize_cuda_version("12.4") == "124"
    end

    test "handles nil" do
      assert WheelSelector.normalize_cuda_version(nil) == nil
    end
  end

  describe "select_wheel/2" do
    test "selects correct PyTorch wheel for CUDA 12.1" do
      Application.put_env(:snakebridge, :hardware_module, MockHardwareCuda)

      wheel_info = WheelSelector.select_wheel("torch", "2.1.0")

      assert wheel_info.variant == "cu121"
      assert wheel_info.index_url =~ "cu121"
    end

    test "selects CPU wheel when no CUDA" do
      Application.put_env(:snakebridge, :hardware_module, MockHardware)

      wheel_info = WheelSelector.select_wheel("torch", "2.1.0")

      assert wheel_info.variant == "cpu"
      assert wheel_info.index_url =~ "cpu"
    end

    test "returns nil variant for non-torch packages" do
      Application.put_env(:snakebridge, :hardware_module, MockHardwareCuda)

      wheel_info = WheelSelector.select_wheel("numpy", "1.26.4")

      assert wheel_info.variant == nil
      assert wheel_info.index_url == nil
    end
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
