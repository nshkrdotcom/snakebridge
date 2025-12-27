defmodule SnakeBridge.PythonRuntimeRunner do
  @moduledoc false

  @behaviour Snakepit.Bootstrap.Runner

  @impl true
  def mix(_task, _args), do: :ok

  @impl true
  def cmd(command, args, opts) do
    opts = Keyword.put_new(opts, :stderr_to_stdout, true)

    {actual_command, actual_args} =
      if String.ends_with?(command, ".sh") do
        {"bash", [command | args]}
      else
        {command, args}
      end

    case System.cmd(actual_command, actual_args, opts) do
      {output, 0} ->
        write_output(output)
        :ok

      {output, status} ->
        write_output(output)
        {:error, {:command_failed, command, status}}
    end
  rescue
    error in ErlangError ->
      {:error, {:command_failed, command, Exception.message(error)}}
  end

  defp write_output(output) do
    if String.trim(output) != "" do
      IO.write(output)
    end
  end
end
