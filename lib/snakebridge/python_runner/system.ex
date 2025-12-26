defmodule SnakeBridge.PythonRunner.System do
  @moduledoc false

  @behaviour SnakeBridge.PythonRunner

  @impl SnakeBridge.PythonRunner
  def run(script, args, opts \\ []) when is_binary(script) and is_list(args) do
    with {:ok, python, _meta} <- Snakepit.PythonRuntime.resolve_executable() do
      env = build_env(opts)
      cmd_opts = Keyword.merge([stderr_to_stdout: true, env: env], Keyword.drop(opts, [:env]))

      case System.cmd(python, ["-c", script | args], cmd_opts) do
        {output, 0} -> {:ok, output}
        {output, status} -> {:error, {:python_exit, status, output}}
      end
    end
  end

  defp build_env(opts) do
    runtime_env = Snakepit.PythonRuntime.runtime_env()

    extra_env =
      Snakepit.PythonRuntime.config()
      |> Map.get(:extra_env, %{})
      |> Enum.to_list()

    user_env =
      opts
      |> Keyword.get(:env, %{})
      |> Enum.to_list()

    runtime_env ++ extra_env ++ user_env
  end
end
