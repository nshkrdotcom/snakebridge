defmodule SnakeBridge.LockTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.{Config, Lock}

  defmodule TestPythonRuntime do
    def runtime_identity do
      {:ok, %{version: "3.12.0", platform: "test-platform", hash: "runtime-hash"}}
    end
  end

  defmodule TestPythonPackages do
    def lock_metadata(_requirements, _opts \\ []) do
      {:ok, %{"numpy" => %{version: "1.26.4"}}}
    end
  end

  setup do
    original_packages = Application.get_env(:snakebridge, :python_packages)
    original_runtime = Application.get_env(:snakebridge, :python_runtime)

    Application.put_env(:snakebridge, :python_packages, TestPythonPackages)
    Application.put_env(:snakebridge, :python_runtime, TestPythonRuntime)

    on_exit(fn ->
      restore_env(:snakebridge, :python_packages, original_packages)
      restore_env(:snakebridge, :python_runtime, original_runtime)
    end)

    :ok
  end

  test "compute_packages_hash is deterministic" do
    packages_a = %{
      "numpy" => %{"version" => "1.26.4"},
      "scipy" => %{"version" => "1.11.4"}
    }

    packages_b = %{
      "scipy" => %{"version" => "1.11.4"},
      "numpy" => %{"version" => "1.26.4"}
    }

    assert Lock.compute_packages_hash(packages_a) == Lock.compute_packages_hash(packages_b)
  end

  test "lock includes package metadata and hash" do
    libraries = [
      %Config.Library{name: :numpy, version: "~> 1.26", python_name: "numpy", module_name: Numpy}
    ]

    config = %Config{libraries: libraries}

    lock = Lock.build(config)

    assert lock["python_packages"] == %{"numpy" => %{version: "1.26.4"}}

    assert lock["environment"]["python_packages_hash"] ==
             "sha256:" <> Lock.compute_packages_hash(lock["python_packages"])

    assert lock["environment"]["python_version"] == "3.12.0"
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
