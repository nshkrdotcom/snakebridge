defmodule SnakeBridge.Lock do
  @moduledoc """
  Manages snakebridge.lock with runtime identity, hardware info, and library versions.

  The lock file captures:
  - Hardware identity (accelerator, CUDA version, CPU features)
  - Platform information (OS, architecture)
  - Python environment (version, packages)
  - Library configurations

  ## Hardware-Aware Lock Files

  The lock file includes hardware information to detect compatibility issues:

      %{
        "environment" => %{
          "hardware" => %{
            "accelerator" => "cuda",
            "cuda_version" => "12.1",
            "gpu_count" => 2,
            "cpu_features" => ["avx", "avx2"]
          },
          "platform" => %{
            "os" => "linux",
            "arch" => "x86_64"
          }
        }
      }

  Use `SnakeBridge.Lock.Verifier` to verify compatibility.
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
    write(lock)
  end

  @spec write(map()) :: :ok
  def write(lock) when is_map(lock) do
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
    hardware = build_hardware_section()
    platform = build_platform_section()

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
        "otp_version" => System.otp_release(),
        "hardware" => hardware,
        "platform" => platform
      },
      "compatibility" => build_compatibility_section(hardware),
      "libraries" => libraries_lock(config),
      "python_packages" => packages
    }
  end

  @doc """
  Builds the hardware section for the lock file.

  Returns a map with hardware identity including accelerator type,
  CUDA version if available, GPU count, and CPU features.
  """
  @spec build_hardware_section() :: map()
  def build_hardware_section do
    identity = hardware_module().identity()
    caps = hardware_module().capabilities()

    base = %{
      "accelerator" => identity["accelerator"],
      "gpu_count" => identity["gpu_count"],
      "cpu_features" => identity["cpu_features"]
    }

    # Add CUDA-specific info if available
    base =
      if caps.cuda do
        base
        |> Map.put("cuda_version", caps.cuda_version)
        |> Map.put("cudnn_version", caps.cudnn_version)
      else
        base
      end

    base
  end

  @doc """
  Builds the platform section for the lock file.
  """
  @spec build_platform_section() :: map()
  def build_platform_section do
    identity = hardware_module().identity()
    platform = identity["platform"] || "unknown-unknown"

    case String.split(platform, "-", parts: 2) do
      [os, arch] ->
        %{"os" => os, "arch" => arch}

      [os] ->
        %{"os" => os, "arch" => "unknown"}

      _ ->
        %{"os" => "unknown", "arch" => "unknown"}
    end
  end

  @doc """
  Builds the compatibility section with minimum requirements.
  """
  @spec build_compatibility_section(map()) :: map()
  def build_compatibility_section(hardware) do
    %{
      "cuda_min" => hardware["cuda_version"],
      "compute_capability_min" => nil
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

  @generator_files [
    "lib/snakebridge/generator.ex",
    "lib/snakebridge/docs.ex",
    "priv/python/snakebridge_types.py",
    "priv/python/snakebridge_adapter.py"
  ]

  @doc """
  Computes the generator hash from generator and adapter source contents.
  """
  @spec generator_hash() :: String.t()
  def generator_hash do
    content = Enum.map_join(@generator_files, "\n", &read_generator_file/1)

    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  defp read_generator_file(relative_path) do
    candidates =
      [
        Application.app_dir(:snakebridge, relative_path),
        Path.join(File.cwd!(), relative_path)
      ]
      |> Enum.uniq()

    Enum.find_value(candidates, "", fn path ->
      case File.read(path) do
        {:ok, content} -> content
        {:error, _} -> nil
      end
    end) || ""
  end

  @doc """
  Checks if the lock was generated with the current generator version.
  """
  @spec verify_generator_unchanged?(map()) :: boolean()
  def verify_generator_unchanged?(lock) do
    lock_hash = get_in(lock, ["environment", "generator_hash"])
    current_hash = generator_hash()
    lock_hash == current_hash
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

  defp hardware_module do
    Application.get_env(:snakebridge, :hardware_module, Snakepit.Hardware)
  end
end
