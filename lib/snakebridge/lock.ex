defmodule SnakeBridge.Lock do
  @moduledoc """
  Manages snakebridge.lock with runtime identity and library versions.
  """

  alias SnakeBridge.Config

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
      case python_runtime_module().runtime_identity() do
        {:ok, identity} -> identity
        {:error, _} -> %{version: "unknown", platform: "unknown", hash: "unknown"}
      end

    packages = get_package_metadata(config)
    packages_hash = "sha256:" <> compute_packages_hash(packages)

    %{
      "version" => version(),
      "environment" => %{
        "snakebridge_version" => version(),
        "generator_hash" => generator_hash(),
        "python_version" => runtime.version,
        "python_platform" => runtime.platform,
        "python_runtime_hash" => runtime.hash,
        "python_packages_hash" => packages_hash,
        "elixir_version" => System.version(),
        "otp_version" => System.otp_release()
      },
      "libraries" => libraries_lock(config),
      "python_packages" => packages
    }
  end

  @doc """
  Deterministic hash from sorted package versions.
  """
  @spec compute_packages_hash(map()) :: String.t()
  def compute_packages_hash(packages) when is_map(packages) do
    packages
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.map_join("\n", fn {name, info} ->
      version = Map.get(info, "version") || Map.get(info, :version) || "unknown"
      "#{name}==#{version}"
    end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Gets package metadata for the lockfile.
  """
  @spec get_package_metadata(Config.t()) :: map()
  def get_package_metadata(config) do
    requirements = SnakeBridge.PythonEnv.derive_requirements(config.libraries)

    if requirements == [] do
      %{}
    else
      case python_packages_module().lock_metadata(requirements, python_packages_opts([])) do
        {:ok, metadata} when is_map(metadata) -> metadata
        {:error, _} -> %{}
      end
    end
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

  defp python_packages_module do
    Application.get_env(:snakebridge, :python_packages, Snakepit.PythonPackages)
  end

  defp python_packages_opts(opts) do
    if python_packages_module() == Snakepit.PythonPackages do
      Keyword.put_new(opts, :runner, SnakeBridge.PythonPackagesRunner)
    else
      opts
    end
  end

  defp python_runtime_module do
    Application.get_env(:snakebridge, :python_runtime, Snakepit.PythonRuntime)
  end
end
