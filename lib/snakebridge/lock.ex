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
          "hash" => nil,
          "config_hash" => library_config_hash(library)
        }
      }
    end)
    |> Map.new()
  end

  @doc false
  def library_config_hash(library) do
    values = [
      {:module_name, module_name_string(library.module_name)},
      {:generate, library.generate},
      {:include, normalize_list(library.include)},
      {:exclude, normalize_list(library.exclude)},
      {:streaming, normalize_list(library.streaming)},
      {:submodules, library.submodules},
      {:public_api, library.public_api},
      {:module_mode, library.module_mode},
      {:module_include, normalize_list(library.module_include)},
      {:module_exclude, normalize_list(library.module_exclude)},
      {:module_depth, library.module_depth},
      {:docs_url, library.docs_url},
      {:docs_manifest, library.docs_manifest},
      {:docs_profile, library.docs_profile},
      {:docs_manifest_hash, file_hash(library.docs_manifest)},
      {:class_method_scope, library.class_method_scope},
      {:max_class_methods, library.max_class_methods},
      {:on_not_found, library.on_not_found},
      {:signature_sources, normalize_list(library.signature_sources)},
      {:strict_signatures, library.strict_signatures},
      {:min_signature_tier, library.min_signature_tier},
      {:stub_search_paths, normalize_list(library.stub_search_paths)},
      {:use_typeshed, library.use_typeshed},
      {:typeshed_path, library.typeshed_path},
      {:stubgen, normalize_stubgen(library.stubgen)}
    ]

    :crypto.hash(:sha256, :erlang.term_to_binary(values))
    |> Base.encode16(case: :lower)
  end

  defp module_name_string(nil), do: nil
  defp module_name_string(module) when is_atom(module), do: Atom.to_string(module)
  defp module_name_string(module), do: to_string(module)

  defp normalize_list(nil), do: []

  defp normalize_list(list) when is_list(list) do
    Enum.map(list, fn
      value when is_atom(value) -> Atom.to_string(value)
      value -> to_string(value)
    end)
  end

  defp normalize_list(value) when is_atom(value), do: [Atom.to_string(value)]
  defp normalize_list(value) when is_binary(value), do: [value]
  defp normalize_list(_), do: []

  defp normalize_stubgen(nil), do: []
  defp normalize_stubgen(list) when is_list(list), do: Enum.sort_by(list, &elem(&1, 0))
  defp normalize_stubgen(_), do: []

  defp file_hash(nil), do: nil
  defp file_hash(path) when not is_binary(path), do: nil

  defp file_hash(path) do
    case File.read(path) do
      {:ok, content} ->
        :crypto.hash(:sha256, content)
        |> Base.encode16(case: :lower)

      {:error, _} ->
        nil
    end
  end

  defp lock_path do
    "snakebridge.lock"
  end

  defp version do
    Application.spec(:snakebridge, :vsn) |> to_string()
  end

  @generator_files [
    "lib/snakebridge/config.ex",
    "lib/snakebridge/compiler/pipeline.ex",
    "lib/snakebridge/introspector.ex",
    "lib/snakebridge/generator.ex",
    "lib/snakebridge/docs.ex",
    "lib/snakebridge/docs/manifest.ex",
    "lib/snakebridge/docs/manifest_builder.ex",
    "lib/snakebridge/docs/markdown_converter.ex",
    "lib/snakebridge/docs/markdown_sanitizer.ex",
    "lib/snakebridge/docs/sphinx_inventory.ex",
    "lib/mix/tasks/compile/snakebridge.ex",
    "priv/python/introspect.py",
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
