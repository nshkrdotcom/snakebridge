defmodule Mix.Tasks.Compile.Snakebridge do
  @moduledoc """
  Mix compiler that runs the SnakeBridge pre-pass (scan → introspect → generate).
  """

  use Mix.Task.Compiler

  alias SnakeBridge.Compiler.Pipeline
  alias SnakeBridge.{Config, Generator.PathMapper, Helpers, Lock, Manifest}

  @impl Mix.Task.Compiler
  def run(_args) do
    Mix.Task.run("loadconfig")

    config = Config.load()

    if Mix.env() in [:dev, :test] and compile_hint_enabled?() do
      SnakeBridge.CompileShell.install()
    end

    cond do
      skip_generation?() -> {:ok, []}
      up_to_date?(config) -> {:ok, []}
      true -> Pipeline.run(config)
    end
  end

  @impl Mix.Task.Compiler
  def manifests do
    Mix.Task.run("loadconfig")
    config = Config.load()

    [
      Path.join(config.metadata_dir, "manifest.json"),
      "snakebridge.lock"
    ]
  end

  @doc false
  defdelegate verify_generated_files_exist!(config), to: Pipeline

  @doc false
  defdelegate verify_generated_files_exist!(config, manifest), to: Pipeline

  @doc false
  defdelegate verify_symbols_present!(config, manifest), to: Pipeline

  defp skip_generation? do
    case System.get_env("SNAKEBRIDGE_SKIP") do
      nil -> false
      value -> truthy_env?(value)
    end
  end

  defp compile_hint_enabled? do
    case System.get_env("SNAKEBRIDGE_COMPILE_HINT") do
      nil -> Application.get_env(:snakebridge, :compile_hint, false)
      value -> truthy_env?(value)
    end
  end

  defp truthy_env?(value) when is_binary(value) do
    value in ["1", "true", "TRUE", "yes", "YES"]
  end

  defp up_to_date?(%Config{} = config) do
    cond do
      config.libraries == [] ->
        true

      strict_mode?(config) ->
        false

      not prerequisites_satisfied?(config) ->
        false

      true ->
        manifest = Manifest.load(config)
        not generate_all_missing?(config, manifest) and not used_missing?(config, manifest)
    end
  end

  defp prerequisites_satisfied?(config) do
    manifest_present?(config) and
      lock_up_to_date?(config) and
      generated_files_present?(config) and
      helpers_present?(config) and
      registry_present?()
  end

  defp strict_mode?(config) do
    System.get_env("SNAKEBRIDGE_STRICT") == "1" or config.strict == true
  end

  defp manifest_present?(config) do
    path = Path.join(config.metadata_dir, "manifest.json")
    File.exists?(path)
  end

  defp lock_up_to_date?(config) do
    case Lock.load() do
      nil ->
        false

      lock ->
        current_version = Application.spec(:snakebridge, :vsn) |> to_string()
        lock_version = get_in(lock, ["environment", "snakebridge_version"]) || lock["version"]

        lock_version == current_version and Lock.verify_generator_unchanged?(lock) and
          libraries_match_lock?(config, lock)
    end
  end

  defp libraries_match_lock?(config, lock) do
    lock_libraries = Map.get(lock, "libraries", %{})

    Enum.all?(config.libraries, fn library ->
      case Map.get(lock_libraries, library.python_name) do
        nil ->
          false

        info ->
          normalize_version(info["requested"]) == normalize_version(library.version) and
            config_hash_matches?(library, info)
      end
    end)
  end

  defp config_hash_matches?(library, info) do
    lock_hash = info["config_hash"]
    current_hash = Lock.library_config_hash(library)
    is_binary(lock_hash) and lock_hash == current_hash
  end

  defp normalize_version(nil), do: nil
  defp normalize_version(:stdlib), do: "stdlib"
  defp normalize_version(value) when is_binary(value), do: value
  defp normalize_version(value), do: to_string(value)

  defp generated_files_present?(config) do
    _ = SnakeBridge.Registry.load()

    Enum.all?(config.libraries, &generated_files_present_for_library?(config, &1))
  end

  defp generated_files_present_for_library?(config, library) do
    legacy_single = Path.join(config.generated_dir, "#{library.python_name}.ex")

    if config.generated_layout == :split and File.exists?(legacy_single) do
      false
    else
      case registry_entry_paths(config, library) do
        {:ok, paths} -> Enum.all?(paths, &File.exists?/1)
        :error -> fallback_generated_files_present?(config, library)
      end
    end
  end

  defp registry_entry_paths(config, library) do
    case SnakeBridge.Registry.get(library.python_name) do
      %{path: base, files: files} when is_list(files) and files != [] ->
        base = Path.expand(base)
        config_base = Path.expand(config.generated_dir)

        if base == config_base do
          {:ok, Enum.map(files, &Path.join(base, &1))}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp fallback_generated_files_present?(config, library) do
    case config.generated_layout do
      :single ->
        path = Path.join(config.generated_dir, "#{library.python_name}.ex")
        File.exists?(path)

      :split ->
        path = PathMapper.module_to_path(library.python_name, config.generated_dir)

        File.exists?(path)
    end
  end

  defp helpers_present?(config) do
    if Helpers.enabled?(config) do
      dir = Path.join(config.generated_dir, "helpers")

      case File.ls(dir) do
        {:ok, files} -> Enum.any?(files, &String.ends_with?(&1, ".ex"))
        {:error, _} -> false
      end
    else
      true
    end
  end

  defp registry_present? do
    registry_path =
      Application.get_env(:snakebridge, :registry_path) ||
        Path.join([File.cwd!(), "priv", "snakebridge", "registry.json"])

    File.exists?(registry_path)
  end

  defp generate_all_missing?(config, manifest) do
    Enum.any?(config.libraries, fn library ->
      library.generate == :all and not manifest_has_library?(manifest, library)
    end)
  end

  defp manifest_has_library?(manifest, library) do
    prefix = library.python_name
    symbols = Map.get(manifest, "symbols", %{})
    classes = Map.get(manifest, "classes", %{})
    modules = Map.get(manifest, "modules", %{})

    Enum.any?(symbols, fn {_key, info} ->
      String.starts_with?(info["python_module"] || "", prefix)
    end) or
      Enum.any?(classes, fn {_key, info} ->
        String.starts_with?(info["python_module"] || "", prefix)
      end) or
      Enum.any?(modules, fn {python_module, info} ->
        python_module = to_string(python_module || info["python_module"] || "")
        String.starts_with?(python_module, prefix)
      end)
  end

  defp used_missing?(config, manifest) do
    used_libraries = Enum.reject(config.libraries, &(&1.generate == :all))

    if used_libraries == [] do
      false
    else
      used_config = %{config | libraries: used_libraries}
      detected = scanner_module().scan_project(used_config)
      Manifest.missing(manifest, detected) != []
    end
  end

  defp scanner_module do
    Application.get_env(:snakebridge, :scanner, SnakeBridge.Scanner)
  end
end
