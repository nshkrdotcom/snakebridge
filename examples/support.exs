defmodule SnakeBridge.Examples.QuietRunner do
  @moduledoc false
  @behaviour Snakepit.Bootstrap.Runner

  alias Elixir.System, as: ErlangSystem

  @impl true
  def mix(task, args) do
    try do
      Mix.Task.run(task, args)
      :ok
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  @impl true
  def cmd(command, args, opts) do
    opts = Keyword.put_new(opts, :stderr_to_stdout, true)

    {actual_command, actual_args} =
      if String.ends_with?(command, ".sh") do
        {"bash", [command | args]}
      else
        {command, args}
      end

    case ErlangSystem.cmd(actual_command, actual_args, opts) do
      {_output, 0} -> :ok
      {_output, status} -> {:error, {:command_failed, command, status}}
    end
  end
end

defmodule SnakeBridge.Examples.Support do
  @moduledoc false

  def start! do
    Application.ensure_all_started(:logger)
    Logger.configure(level: :warning)

    Application.put_env(:snakepit, :log_level, :none)
    Application.put_env(:snakepit, :env_doctor_runner, SnakeBridge.Examples.QuietRunner)

    Application.ensure_all_started(:snakebridge)
    :ok
  end
end
