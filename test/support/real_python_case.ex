defmodule SnakeBridge.RealPythonCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Snakepit.Adapters.GRPCPython

  @pool_ready_timeout 30_000

  using do
    quote do
      use ExUnit.Case, async: false
      import SnakeBridge.RealPythonCase, only: [setup_real_python: 1]
      setup_all :setup_real_python
    end
  end

  def setup_real_python(context) do
    case ensure_real_python() do
      :ok -> context
      {:skip, reason} -> %{context | skip: reason}
    end
  end

  defp ensure_real_python do
    with {:ok, python} <- resolve_python(),
         :ok <- ensure_python_deps(python) do
      ensure_snakepit_pool()
    end
  end

  defp resolve_python do
    python =
      Application.get_env(:snakepit, :python_executable) ||
        System.get_env("SNAKEPIT_PYTHON") ||
        GRPCPython.executable_path() ||
        System.find_executable("python3")

    if is_binary(python) do
      {:ok, python}
    else
      {:skip, "python3 not available"}
    end
  end

  defp ensure_python_deps(python) do
    env = [{"PYTHONPATH", build_pythonpath()}]

    case System.cmd(python, ["-c", "import grpc, google.protobuf, snakebridge_adapter"], env: env) do
      {_output, 0} ->
        :ok

      {output, _status} ->
        {:skip, "python deps missing (grpc/protobuf/snakebridge_adapter): #{String.trim(output)}"}
    end
  end

  defp ensure_snakepit_pool do
    configure_snakepit()

    if started_app?(:snakepit) and Process.whereis(Snakepit.Pool) == nil do
      Application.stop(:snakepit)
    end

    case Application.ensure_all_started(:snakepit) do
      {:ok, _} -> await_pool_ready()
      {:error, reason} -> {:skip, "snakepit failed to start: #{inspect(reason)}"}
    end
  end

  defp await_pool_ready do
    case Snakepit.Pool.await_ready(Snakepit.Pool, @pool_ready_timeout) do
      :ok -> :ok
      {:error, reason} -> {:skip, "snakepit pool not ready: #{inspect(reason)}"}
    end
  end

  defp configure_snakepit do
    Application.put_env(:snakepit, :pooling_enabled, true)

    if Application.get_env(:snakepit, :adapter_module) == nil do
      Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.GRPCPython)
    end

    pool_config =
      :snakepit
      |> Application.get_env(:pool_config, %{})
      |> normalize_config_input()
      |> Map.put_new(:pool_size, 2)
      |> Map.update(:adapter_args, default_adapter_args(), &ensure_adapter_args/1)

    Application.put_env(:snakepit, :pool_config, pool_config)
  end

  defp ensure_adapter_args(args) when is_list(args) do
    if Enum.any?(args, fn arg ->
         is_binary(arg) and (arg == "--adapter" or String.starts_with?(arg, "--adapter="))
       end) do
      args
    else
      args ++ default_adapter_args()
    end
  end

  defp ensure_adapter_args(_), do: default_adapter_args()

  defp default_adapter_args do
    ["--adapter", "snakebridge_adapter.SnakeBridgeAdapter"]
  end

  defp normalize_config_input(nil), do: %{}
  defp normalize_config_input(%{} = map), do: map
  defp normalize_config_input(list) when is_list(list), do: Map.new(list)
  defp normalize_config_input(_), do: %{}

  defp build_pythonpath do
    priv_snakebridge = Path.join(File.cwd!(), "priv/python")

    snakepit_priv_python =
      case :code.priv_dir(:snakepit) do
        {:error, _} -> nil
        priv_dir -> Path.join([to_string(priv_dir), "python"])
      end

    snakebridge_priv_python =
      case :code.priv_dir(:snakebridge) do
        {:error, _} -> nil
        priv_dir -> Path.join([to_string(priv_dir), "python"])
      end

    path_sep =
      case :os.type() do
        {:win32, _} -> ";"
        _ -> ":"
      end

    [
      System.get_env("PYTHONPATH"),
      priv_snakebridge,
      snakepit_priv_python,
      snakebridge_priv_python
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
    |> Enum.join(path_sep)
  end

  defp started_app?(app) do
    Enum.any?(Application.started_applications(), fn {started, _, _} -> started == app end)
  end
end
