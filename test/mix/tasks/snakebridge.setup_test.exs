defmodule Mix.Tasks.Snakebridge.SetupTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Snakebridge.Setup

  defmodule TestPythonPackages do
    def ensure!(spec, opts) do
      send(self(), {:ensure!, spec, opts})
      :ok
    end

    def check_installed(requirements, _opts \\ []) do
      send(self(), {:check_installed, requirements})
      Process.get(:check_result, {:ok, :all_installed})
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
    end)

    :ok
  end

  test "--check raises when packages are missing" do
    fixture_path = Path.expand("../../fixtures/strict_project", __DIR__)

    Mix.Project.in_project(:strict_project, fixture_path, fn _ ->
      Mix.Task.reenable("snakebridge.setup")
      Process.put(:check_result, {:ok, {:missing, ["numpy"]}})

      assert_raise Mix.Error, fn ->
        Setup.run(["--check"])
      end
    end)
  end

  test "installs packages with options" do
    fixture_path = Path.expand("../../fixtures/strict_project", __DIR__)

    Mix.Project.in_project(:strict_project, fixture_path, fn _ ->
      Mix.Task.reenable("snakebridge.setup")

      Setup.run(["--upgrade", "--verbose"])

      assert_received {:ensure!, {:list, ["numpy~=1.26"]}, opts}
      assert Keyword.get(opts, :upgrade) == true
      assert Keyword.get(opts, :quiet) == false
    end)
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
