defmodule SnakeBridge.IntrospectorTest do
  use ExUnit.Case, async: false

  import Mox
  alias SnakeBridge.IntrospectionError

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    original = Application.get_env(:snakebridge, :python_runner)

    on_exit(fn ->
      if original do
        Application.put_env(:snakebridge, :python_runner, original)
      else
        Application.delete_env(:snakebridge, :python_runner)
      end
    end)

    :ok
  end

  test "uses configured python runner for introspection" do
    Application.put_env(:snakebridge, :python_runner, SnakeBridge.PythonRunnerMock)

    library = %SnakeBridge.Config.Library{
      name: :numpy,
      python_name: "numpy",
      module_name: Numpy
    }

    expect(SnakeBridge.PythonRunnerMock, :run, fn script, args, _opts ->
      assert is_binary(script)
      assert args == ["numpy", "[\"mean\"]"]
      {:ok, "[{\"name\":\"mean\"}]"}
    end)

    assert {:ok, [%{"name" => "mean"}]} = SnakeBridge.Introspector.introspect(library, [:mean])
  end

  test "classifies python errors from the runner" do
    Application.put_env(:snakebridge, :python_runner, SnakeBridge.PythonRunnerMock)

    library = %SnakeBridge.Config.Library{
      name: :numpy,
      python_name: "numpy",
      module_name: Numpy
    }

    output = "Traceback...\\nModuleNotFoundError: No module named 'numpy'"

    expect(SnakeBridge.PythonRunnerMock, :run, fn _script, _args, _opts ->
      {:error, {:python_exit, 1, output}}
    end)

    assert {:error, %IntrospectionError{type: :package_not_found, package: "numpy"}} =
             SnakeBridge.Introspector.introspect(library, [:mean])
  end
end
