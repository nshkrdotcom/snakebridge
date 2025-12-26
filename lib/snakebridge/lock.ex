defmodule SnakeBridge.Lock do
  @moduledoc """
  Manages snakebridge.lock with runtime identity and library versions.
  """

  @spec load() :: map() | nil
  def load do
    case File.read(lock_path()) do
      {:ok, content} -> Jason.decode!(content)
      {:error, :enoent} -> nil
    end
  end

  @spec update(SnakeBridge.Config.t()) :: :ok
  def update(config) do
    lock = build(config)

    lock
    |> Jason.encode!(pretty: true)
    |> then(&File.write!(lock_path(), &1))
  end

  @spec build(SnakeBridge.Config.t()) :: map()
  def build(config) do
    runtime =
      case Snakepit.PythonRuntime.runtime_identity() do
        {:ok, identity} -> identity
        {:error, _} -> %{version: "unknown", platform: "unknown", hash: "unknown"}
      end

    %{
      "version" => version(),
      "environment" => %{
        "snakebridge_version" => version(),
        "generator_hash" => generator_hash(),
        "python_version" => runtime.version,
        "python_platform" => runtime.platform,
        "python_runtime_hash" => runtime.hash,
        "elixir_version" => System.version(),
        "otp_version" => System.otp_release()
      },
      "libraries" => libraries_lock(config)
    }
  end

  defp libraries_lock(config) do
    config.libraries
    |> Enum.map(fn library ->
      {
        library.python_name,
        %{
          "requested" => library.version,
          "resolved" => library.version,
          "hash" => nil
        }
      }
    end)
    |> Map.new()
  end

  defp lock_path do
    "snakebridge.lock"
  end

  defp version do
    Application.spec(:snakebridge, :vsn) |> to_string()
  end

  defp generator_hash do
    :crypto.hash(:sha256, version()) |> Base.encode16(case: :lower)
  end
end
