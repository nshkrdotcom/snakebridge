defmodule Mix.Tasks.Compile.SnakebridgeTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Compile.Snakebridge

  defmodule TestScanner do
    def scan_project(_config) do
      [{Numpy, :array, 1}]
    end
  end

  setup do
    original = System.get_env("SNAKEBRIDGE_STRICT")
    original_scanner = Application.get_env(:snakebridge, :scanner)

    Application.put_env(:snakebridge, :scanner, TestScanner)

    on_exit(fn ->
      case original do
        nil -> System.delete_env("SNAKEBRIDGE_STRICT")
        value -> System.put_env("SNAKEBRIDGE_STRICT", value)
      end

      restore_env(:snakebridge, :scanner, original_scanner)
    end)

    :ok
  end

  test "strict mode fails when symbols are missing" do
    fixture_path = fixture_path()
    manifest_dir = Path.join(fixture_path, ".snakebridge")

    File.rm_rf!(manifest_dir)
    System.put_env("SNAKEBRIDGE_STRICT", "1")

    Mix.Project.in_project(:strict_project, fixture_path, fn _ ->
      Mix.Task.reenable("compile.snakebridge")

      assert_raise SnakeBridge.CompileError, fn ->
        Snakebridge.run([])
      end
    end)
  end

  test "strict mode succeeds when manifest covers all symbols" do
    fixture_path = fixture_path()
    manifest_path = Path.join([fixture_path, ".snakebridge", "manifest.json"])
    generated_path = Path.join([fixture_path, "lib", "snakebridge_generated", "numpy.ex"])

    key = SnakeBridge.Manifest.symbol_key({Numpy, :array, 1})

    write_manifest(manifest_path, %{
      key => %{
        "module" => "Numpy",
        "function" => "array",
        "name" => "array",
        "python_module" => "numpy"
      }
    })

    File.mkdir_p!(Path.dirname(generated_path))

    File.write!(
      generated_path,
      """
      defmodule Numpy do
        @moduledoc false

        def array(x, opts \\\\ []) do
          SnakeBridge.Runtime.call(__MODULE__, :array, [x], opts)
        end
      end
      """
    )

    System.put_env("SNAKEBRIDGE_STRICT", "1")

    Mix.Project.in_project(:strict_project, fixture_path, fn _ ->
      Mix.Task.reenable("compile.snakebridge")

      assert {:ok, []} = Snakebridge.run([])
    end)
  end

  defp write_manifest(path, symbols) do
    File.mkdir_p!(Path.dirname(path))

    manifest = %{
      "version" => "0.4.0",
      "symbols" => symbols,
      "classes" => %{}
    }

    File.write!(path, Jason.encode!(manifest))
  end

  defp fixture_path do
    Path.expand("../../../fixtures/strict_project", __DIR__)
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
