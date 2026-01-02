defmodule Demo do
  @moduledoc """
  Run with: mix run -e Demo.run
  """

  alias SnakeBridge.Examples
  alias Snakepit.Bridge.{SessionStore, ToolRegistry}

  @bridge_client_env "SNAKEBRIDGE_BRIDGE_CLIENT"
  @grpc_address "localhost:50051"

  def run do
    configure_snakepit()

    SnakeBridge.run_as_script(fn ->
      Examples.reset_failures()

      IO.puts("Bridge Client Example")
      IO.puts("---------------------")

      session_id = "bridge_client_#{System.system_time(:millisecond)}"

      case setup_bridge_tools(session_id) do
        :ok ->
          maybe_run_bridge_client(session_id)

        {:error, reason} ->
          IO.puts("Failed to register tools: #{inspect(reason)}")
          Examples.record_failure()
      end

      Examples.assert_no_failures!()
    end)
    |> Examples.assert_script_ok()
  end

  defp configure_snakepit do
    Application.put_env(:snakepit, :pooling_enabled, true)
    Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.GRPCPython)

    pool_config =
      :snakepit
      |> Application.get_env(:pool_config, %{})
      |> Map.merge(%{
        pool_size: 1,
        adapter_args: [
          "--adapter",
          "bridge_client_example_adapter.BridgeClientExampleAdapter"
        ],
        adapter_env: [
          {"PYTHONPATH", pythonpath()}
        ]
      })

    Application.put_env(:snakepit, :pool_config, pool_config)
  end

  defp setup_bridge_tools(session_id) do
    with :ok <- ensure_session(session_id),
         {:ok, worker_id} <- fetch_worker_id(),
         :ok <- register_tool(session_id, worker_id, "add", %{}),
         :ok <-
           register_tool(session_id, worker_id, "stream_count", %{supports_streaming: true}) do
      :ok
    end
  end

  defp ensure_session(session_id) do
    case SessionStore.create_session(session_id) do
      {:ok, _} -> :ok
      {:error, :already_exists} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_worker_id do
    case Snakepit.Pool.list_workers(Snakepit.Pool) do
      [worker_id | _] -> {:ok, worker_id}
      [] -> {:error, :no_workers}
    end
  end

  defp register_tool(session_id, worker_id, name, metadata) do
    case ToolRegistry.register_python_tool(session_id, name, worker_id, metadata) do
      :ok -> :ok
      {:error, {:duplicate_tool, _}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_run_bridge_client(session_id) do
    if env_truthy?(@bridge_client_env) do
      run_bridge_client(session_id)
    else
      IO.puts("Set #{@bridge_client_env}=1 to run the Python BridgeClient demo.")
    end
  end

  defp run_bridge_client(session_id) do
    python = System.get_env("SNAKEPIT_PYTHON") || System.find_executable("python3")

    if is_binary(python) do
      case ensure_python_deps(python) do
        :ok ->
          script_path = Path.expand("../priv/python/bridge_client_demo.py", __DIR__)

          env = [
            {"PYTHONPATH", pythonpath()},
            {"SNAKEPIT_GRPC_ADDR", @grpc_address},
            {"SNAKEPIT_SESSION_ID", session_id}
          ]

          {output, status} = System.cmd(python, [script_path], env: env, stderr_to_stdout: true)
          IO.puts(output)

          if status != 0 do
            IO.puts("BridgeClient demo failed (status #{status}).")
            Examples.record_failure()
          end

        {:error, reason} ->
          IO.puts("BridgeClient demo skipped: #{reason}")
      end
    else
      IO.puts("BridgeClient demo skipped: python3 not available.")
    end
  end

  defp ensure_python_deps(python) do
    {output, status} =
      System.cmd(python, ["-c", "import grpc, google.protobuf"],
        env: [{"PYTHONPATH", pythonpath()}]
      )

    if status == 0 do
      :ok
    else
      {:error, String.trim(output)}
    end
  end

  defp pythonpath do
    example_root = Path.expand("..", __DIR__)
    repo_root = Path.expand("../../..", __DIR__)

    snakepit_priv = Path.join([repo_root, "deps", "snakepit", "priv", "python"])
    snakebridge_priv = Path.join([repo_root, "priv", "python"])
    example_priv = Path.join([example_root, "priv", "python"])

    path_sep =
      case :os.type() do
        {:win32, _} -> ";"
        _ -> ":"
      end

    [System.get_env("PYTHONPATH"), snakepit_priv, snakebridge_priv, example_priv]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
    |> Enum.join(path_sep)
  end

  defp env_truthy?(key) do
    case System.get_env(key) do
      nil -> false
      value -> String.downcase(value) in ["1", "true", "yes", "on"]
    end
  end
end
