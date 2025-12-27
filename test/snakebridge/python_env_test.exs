defmodule SnakeBridge.PythonEnvTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.{Config, PythonEnv}

  defmodule TestPythonPackages do
    def ensure!(spec, opts) do
      send(self(), {:ensure!, spec, opts})
      :ok
    end

    def check_installed(requirements, _opts \\ []) do
      send(self(), {:check_installed, requirements})
      Process.get(:check_result, {:ok, :all_installed})
    end

    def lock_metadata(requirements, _opts \\ []) do
      send(self(), {:lock_metadata, requirements})
      Process.get(:lock_metadata_result, {:ok, %{}})
    end
  end

  setup do
    original_packages = Application.get_env(:snakebridge, :python_packages)
    original_python = Application.get_env(:snakepit, :python)

    Application.put_env(:snakebridge, :python_packages, TestPythonPackages)
    Application.put_env(:snakepit, :python, managed: false)

    on_exit(fn ->
      restore_env(:snakebridge, :python_packages, original_packages)
      restore_env(:snakepit, :python, original_python)
      Process.delete(:check_result)
      Process.delete(:lock_metadata_result)
    end)

    :ok
  end

  test "derive_requirements skips stdlib libraries" do
    libraries = [
      %Config.Library{name: :json, version: :stdlib, python_name: "json", module_name: Json},
      %Config.Library{name: :numpy, version: "~> 1.26", python_name: "numpy", module_name: Numpy}
    ]

    assert PythonEnv.derive_requirements(libraries) == ["numpy~=1.26"]
  end

  test "derive_requirements translates version constraints" do
    libraries = [
      %Config.Library{name: :sympy, version: "~> 1.12", python_name: "sympy", module_name: Sympy},
      %Config.Library{name: :numpy, version: "1.26.4", python_name: "numpy", module_name: Numpy}
    ]

    assert PythonEnv.derive_requirements(libraries) == ["sympy~=1.12", "numpy==1.26.4"]
  end

  test "derive_requirements honors pypi_package override" do
    libraries = [
      %Config.Library{
        name: :pillow,
        version: "~> 10.0",
        python_name: "PIL",
        pypi_package: "pillow",
        module_name: Pillow
      }
    ]

    assert PythonEnv.derive_requirements(libraries) == ["pillow~=10.0"]
  end

  test "derive_requirements includes extras" do
    libraries = [
      %Config.Library{
        name: :torch,
        version: "~> 2.0",
        python_name: "torch",
        extras: ["cuda", "dev"],
        module_name: Torch
      }
    ]

    assert PythonEnv.derive_requirements(libraries) == ["torch[cuda,dev]~=2.0"]
  end

  test "ensure! installs packages when auto_install enabled" do
    libraries = [
      %Config.Library{name: :numpy, version: "~> 1.26", python_name: "numpy", module_name: Numpy}
    ]

    config = %Config{libraries: libraries, auto_install: :always, strict: false, verbose: false}

    assert :ok = PythonEnv.ensure!(config)
    assert_received {:ensure!, {:list, ["numpy~=1.26"]}, opts}
    assert Keyword.get(opts, :quiet) == true
  end

  test "ensure! verifies environment in strict mode" do
    libraries = [
      %Config.Library{name: :numpy, version: "~> 1.26", python_name: "numpy", module_name: Numpy}
    ]

    config = %Config{libraries: libraries, auto_install: :always, strict: true}

    Process.put(:check_result, {:ok, :all_installed})

    assert :ok = PythonEnv.ensure!(config)
    assert_received {:check_installed, ["numpy~=1.26"]}
    refute_received {:ensure!, _, _}
  end

  test "verify_environment! returns :ok when all installed" do
    libraries = [
      %Config.Library{name: :numpy, version: "~> 1.26", python_name: "numpy", module_name: Numpy}
    ]

    config = %Config{libraries: libraries}

    Process.put(:check_result, {:ok, :all_installed})

    assert :ok = PythonEnv.verify_environment!(config)
  end

  test "verify_environment! raises when packages missing" do
    libraries = [
      %Config.Library{name: :numpy, version: "~> 1.26", python_name: "numpy", module_name: Numpy}
    ]

    config = %Config{libraries: libraries}

    Process.put(:check_result, {:ok, {:missing, ["numpy"]}})

    assert_raise SnakeBridge.EnvironmentError, fn ->
      PythonEnv.verify_environment!(config)
    end
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
