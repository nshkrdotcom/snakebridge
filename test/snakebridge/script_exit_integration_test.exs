defmodule SnakeBridge.ScriptExitIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :real_python

  @script_path Path.expand("../support/scripts/script_exit.exs", __DIR__)
  @project_root Path.expand("../..", __DIR__)

  test "explicit exit_mode stop exits before post-run output" do
    {output, status} = run_script(["--exit-mode", "stop", "--print-after"])

    assert status == 0
    refute output =~ "SCRIPT_AFTER"
  end

  test "SNAKEPIT_SCRIPT_EXIT=halt overrides wrapper defaults" do
    {output, status} =
      run_script(["--print-after"],
        env: %{"SNAKEPIT_SCRIPT_EXIT" => "halt"}
      )

    assert status == 0
    refute output =~ "SCRIPT_AFTER"
  end

  test "embedded usage keeps Snakepit running" do
    {output, status} =
      run_script(["--prestart-snakepit", "--assert-snakepit-running", "--print-after"])

    assert status == 0
    assert output =~ "SCRIPT_AFTER"
  end

  test "explicit exit_mode halt exits with status 1 on exception" do
    {_output, status} = run_script(["--exit-mode", "halt", "--raise"])

    assert status == 1
  end

  defp run_script(args, opts \\ []) do
    no_halt = Keyword.get(opts, :no_halt, false)
    timeout_ms = Keyword.get(opts, :timeout_ms, 10_000)
    env = Keyword.get(opts, :env, %{}) |> Map.put_new("MIX_ENV", "test")

    mix_args = build_mix_args(no_halt, args)

    task =
      Task.async(fn ->
        System.cmd("mix", mix_args,
          cd: @project_root,
          env: Map.to_list(env),
          stderr_to_stdout: true
        )
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        result

      nil ->
        flunk("mix run timed out after #{timeout_ms}ms")

      {:exit, reason} ->
        flunk("mix run crashed: #{inspect(reason)}")
    end
  end

  defp build_mix_args(no_halt, script_args) do
    base = ["run"]
    base = if no_halt, do: base ++ ["--no-halt"], else: base
    base ++ [@script_path] ++ script_args
  end
end
