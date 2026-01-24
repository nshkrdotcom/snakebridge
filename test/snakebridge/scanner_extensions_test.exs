defmodule SnakeBridge.ScannerExtensionsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias SnakeBridge.{Config, Scanner}

  test "scan_extensions includes .exs when configured" do
    tmp_dir = SnakeBridge.TestHelpers.tmp_path()
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    File.write!(
      Path.join(tmp_dir, "example.exs"),
      """
      defmodule ScannerExtensionsFixture do
        def run do
          Examplelib.foo(1)
        end
      end
      """
    )

    library =
      struct(Config.Library,
        name: :examplelib,
        python_name: "examplelib",
        module_name: Examplelib
      )

    config =
      struct(Config,
        libraries: [library],
        generated_dir: "lib/snakebridge_generated",
        scan_paths: [tmp_dir],
        scan_extensions: [".exs"],
        scan_exclude: []
      )

    assert [{Examplelib, :foo, 1}] == Scanner.scan_project(config)
  end
end
