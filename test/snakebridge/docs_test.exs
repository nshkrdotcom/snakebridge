defmodule SnakeBridge.DocsTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    original_runner = Application.get_env(:snakebridge, :python_runner)
    original_docs = Application.get_env(:snakebridge, :docs)

    on_exit(fn ->
      if original_runner do
        Application.put_env(:snakebridge, :python_runner, original_runner)
      else
        Application.delete_env(:snakebridge, :python_runner)
      end

      if original_docs do
        Application.put_env(:snakebridge, :docs, original_docs)
      else
        Application.delete_env(:snakebridge, :docs)
      end
    end)

    :ok
  end

  defmodule Numpy do
    def __snakebridge_python_name__, do: "numpy"
  end

  defmodule Math do
    def __functions__ do
      [
        {:sqrt, 1, __MODULE__, "Return the square root."},
        {:sin, 1, __MODULE__, "Return the sine."},
        {:cos, 1, __MODULE__, "Return the cosine."}
      ]
    end
  end

  test "fetches docs from python runtime when source is :python" do
    Application.put_env(:snakebridge, :python_runner, SnakeBridge.PythonRunnerMock)
    Application.put_env(:snakebridge, :docs, source: :python, cache_enabled: false)

    expect(SnakeBridge.PythonRunnerMock, :run, fn _script, ["numpy", "mean"], _opts ->
      {:ok, "numpy.mean doc"}
    end)

    assert SnakeBridge.Docs.get(Numpy, :mean) == "numpy.mean doc"
  end

  test "search returns ranked matches from discovery data" do
    results = SnakeBridge.Docs.search(Math, "sq")

    assert [%{name: :sqrt, summary: "Return the square root.", relevance: relevance}] = results
    assert relevance >= 0.9
  end
end
