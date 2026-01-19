defmodule Demo do
  @moduledoc """
  Run with: mix run --no-start -e Demo.run
  """

  alias SnakeBridge.Compiler.Pipeline
  alias SnakeBridge.Config
  alias SnakeBridge.Examples

  def run do
    SnakeBridge.run_as_script(fn ->
      Examples.reset_failures()

      IO.puts("Strict Signature Mode Example")
      IO.puts("------------------------------")

      step("Normal wrappers (non-strict)")
      print_result(StrictModeExample.add(2, 3))
      print_result(StrictModeExample.multiply(4, 5))

      step("Strict signature tier check")
      strict_config = build_config(:stub)
      run_strict_check(strict_config, expect_failure: true)

      step("Relax min signature tier to variadic")
      relaxed_config = build_config(:variadic)
      run_strict_check(relaxed_config, expect_failure: false)

      Examples.assert_no_failures!()
    end)
    |> Examples.assert_script_ok()
  end

  defp step(title) do
    IO.puts("")
    IO.puts("== #{title} ==")
  end

  defp print_result({:ok, value}) do
    IO.puts("Result: {:ok, #{inspect(value)}}")
  end

  defp print_result({:error, reason}) do
    IO.puts("Result: {:error, #{inspect(reason)}}")
    Examples.record_failure()
  end

  defp print_result(other) do
    IO.puts("Result: #{inspect(other)}")
  end

  defp run_strict_check(config, expect_failure: expect_failure) do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "snakebridge_strict_signatures_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    config = %Config{
      config
      | generated_dir: Path.join(tmp_dir, "generated"),
        metadata_dir: Path.join(tmp_dir, "metadata")
    }

    try do
      Pipeline.run(config)

      if expect_failure do
        IO.puts("Unexpected: strict mode passed")
        Examples.record_failure()
      else
        IO.puts("Strict mode passed")
      end
    rescue
      error in SnakeBridge.CompileError ->
        if expect_failure do
          IO.puts("Strict mode failed as expected")
          IO.puts(Exception.message(error))
        else
          IO.puts("Unexpected strict mode failure: #{Exception.message(error)}")
          Examples.record_failure()
        end
    end
  end

  defp build_config(min_signature_tier) do
    base_config = Config.load()

    %Config{
      base_config
      | auto_install: :never,
        strict_signatures: true,
        min_signature_tier: min_signature_tier,
        generated_dir: "generated",
        metadata_dir: "metadata",
        helper_paths: [],
        helper_pack_enabled: false,
        helper_allowlist: [],
        inline_enabled: false,
        scan_paths: [],
        scan_exclude: []
    }
  end
end
