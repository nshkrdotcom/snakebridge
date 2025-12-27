defmodule SnakeBridge.PythonPackagesRunner do
  @moduledoc false

  @behaviour Snakepit.PythonPackages.Runner

  @impl true
  @doc false
  def cmd(command, args, opts) do
    {timeout, opts} = Keyword.pop(opts, :timeout)

    run = fn -> System.cmd(command, args, opts) end

    if is_integer(timeout) do
      task = Task.async(run)

      case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> result
        nil -> {"Command timed out after #{timeout}ms", 124}
      end
    else
      run.()
    end
  rescue
    error in ErlangError ->
      {Exception.message(error), 127}
  end
end
