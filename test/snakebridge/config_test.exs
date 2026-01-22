defmodule SnakeBridge.ConfigTest do
  use ExUnit.Case, async: false

  alias SnakeBridge.Config

  setup do
    original_auto_install = Application.get_env(:snakebridge, :auto_install)

    on_exit(fn ->
      restore_env(:snakebridge, :auto_install, original_auto_install)
    end)

    :ok
  end

  test "parse_libraries includes pypi_package and extras" do
    [library] =
      Config.parse_libraries(
        pillow: [
          version: "~> 10.0",
          python_name: "PIL",
          pypi_package: "pillow",
          docs_url: "https://pillow.readthedocs.io/",
          extras: ["cuda"]
        ]
      )

    assert library.pypi_package == "pillow"
    assert library.docs_url == "https://pillow.readthedocs.io/"
    assert library.extras == ["cuda"]
  end

  test "load reads auto_install from application env" do
    Application.put_env(:snakebridge, :auto_install, :always)

    config = Config.load()

    assert config.auto_install == :always
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
