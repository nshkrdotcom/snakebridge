defmodule SnakeBridge.Lock.Verifier do
  @moduledoc """
  Verifies hardware and environment compatibility between the lock file and current system.

  The verifier compares the hardware identity in the lock file against the current
  system's capabilities to detect potential compatibility issues before runtime.

  ## Verification Levels

  - `:ok` - Full compatibility, no issues detected
  - `{:warning, warnings}` - Minor differences that may work but could cause issues
  - `{:error, errors}` - Incompatible environment that will likely fail

  ## Examples

      # Verify lock file compatibility
      lock = SnakeBridge.Lock.load()
      case SnakeBridge.Lock.Verifier.verify(lock) do
        :ok ->
          IO.puts("Environment compatible")
        {:warning, warnings} ->
          Enum.each(warnings, &IO.warn/1)
        {:error, errors} ->
          raise SnakeBridge.EnvironmentError, message: Enum.join(errors, "; ")
      end

  """

  @type verification_result :: :ok | {:warning, [String.t()]} | {:error, [String.t()]}

  @doc """
  Verifies the lock file against the current hardware environment.

  Returns `:ok` if compatible, `{:warning, warnings}` for minor issues,
  or `{:error, errors}` for critical incompatibilities.
  """
  @spec verify(map() | nil) :: verification_result()
  def verify(nil) do
    start_time = System.monotonic_time()
    SnakeBridge.Telemetry.lock_verify(start_time, :error, ["No lock file provided"])
    {:error, ["No lock file provided"]}
  end

  def verify(lock) when is_map(lock) do
    start_time = System.monotonic_time()
    errors = []
    warnings = []

    current = hardware_module().identity()
    lock_env = Map.get(lock, "environment", %{})
    lock_hardware = Map.get(lock_env, "hardware", %{})
    lock_platform = Map.get(lock_env, "platform", %{})
    compatibility = Map.get(lock, "compatibility", %{})

    # Check platform
    {platform_errors, platform_warnings} = verify_platform(lock_platform, current)
    errors = errors ++ platform_errors
    warnings = warnings ++ platform_warnings

    # Check accelerator/CUDA
    {accel_errors, accel_warnings} = verify_accelerator(lock_hardware, current, compatibility)
    errors = errors ++ accel_errors
    warnings = warnings ++ accel_warnings

    # Check CPU features if required
    {feature_errors, feature_warnings} = verify_cpu_features(lock_hardware, current)
    errors = errors ++ feature_errors
    warnings = warnings ++ feature_warnings

    result =
      cond do
        errors != [] -> {:error, errors}
        warnings != [] -> {:warning, warnings}
        true -> :ok
      end

    case result do
      :ok -> SnakeBridge.Telemetry.lock_verify(start_time, :ok, [])
      {:warning, warn} -> SnakeBridge.Telemetry.lock_verify(start_time, :warning, warn)
      {:error, errs} -> SnakeBridge.Telemetry.lock_verify(start_time, :error, errs)
    end

    result
  end

  @doc """
  Verifies the lock file and raises on error.

  Returns `:ok` on success or raises `SnakeBridge.EnvironmentError`.
  Warnings are logged but do not raise.
  """
  @spec verify!(map() | nil) :: :ok
  def verify!(lock) do
    case verify(lock) do
      :ok ->
        :ok

      {:warning, warnings} ->
        Enum.each(warnings, &Mix.shell().info("Warning: #{&1}"))
        :ok

      {:error, errors} ->
        raise SnakeBridge.EnvironmentError,
          message: "Lock file incompatible: #{Enum.join(errors, "; ")}"
    end
  end

  # Private functions

  defp verify_platform(lock_platform, _current) when map_size(lock_platform) == 0 do
    {[], []}
  end

  defp verify_platform(lock_platform, current) do
    errors = []
    warnings = []

    current_platform = current["platform"] || ""
    [current_os, current_arch] = parse_platform(current_platform)

    lock_os = Map.get(lock_platform, "os", "")
    lock_arch = Map.get(lock_platform, "arch", "")

    errors =
      if lock_os != "" and lock_os != current_os do
        ["Platform mismatch: lock requires #{lock_os}, current is #{current_os}" | errors]
      else
        errors
      end

    errors =
      if lock_arch != "" and lock_arch != current_arch do
        ["Architecture mismatch: lock requires #{lock_arch}, current is #{current_arch}" | errors]
      else
        errors
      end

    {errors, warnings}
  end

  defp verify_accelerator(lock_hardware, _current, _compatibility)
       when map_size(lock_hardware) == 0 do
    {[], []}
  end

  defp verify_accelerator(lock_hardware, current, _compatibility) do
    lock_accelerator = Map.get(lock_hardware, "accelerator", "cpu")
    current_accelerator = current["accelerator"] || "cpu"
    current_caps = hardware_module().capabilities()
    lock_cuda_version = Map.get(lock_hardware, "cuda_version")
    current_cuda_version = current_caps.cuda_version

    check_accelerator_compatibility(
      lock_accelerator,
      current_accelerator,
      current_caps,
      lock_cuda_version,
      current_cuda_version
    )
  end

  defp check_accelerator_compatibility(
         "cuda",
         _current_accel,
         %{cuda: false},
         _lock_ver,
         _cur_ver
       ) do
    {["Lock requires CUDA but no CUDA available on current system"], []}
  end

  defp check_accelerator_compatibility("mps", _current_accel, %{mps: false}, _lock_ver, _cur_ver) do
    {["Lock requires MPS but MPS not available (requires macOS with Apple Silicon)"], []}
  end

  defp check_accelerator_compatibility("cuda", _current_accel, %{cuda: true}, lock_ver, cur_ver) do
    check_cuda_version_compatibility(lock_ver, cur_ver)
  end

  defp check_accelerator_compatibility("cuda", "cpu", _caps, _lock_ver, _cur_ver) do
    {[], ["Lock was built with CUDA, falling back to CPU"]}
  end

  defp check_accelerator_compatibility(_lock_accel, _current_accel, _caps, _lock_ver, _cur_ver) do
    {[], []}
  end

  defp check_cuda_version_compatibility(lock_version, current_version) do
    lock_major = major_version(lock_version)
    current_major = major_version(current_version)

    cond do
      lock_major != current_major ->
        {[], ["CUDA version mismatch: lock has #{lock_version}, current has #{current_version}"]}

      lock_version != current_version ->
        {[], ["CUDA version differs: lock has #{lock_version}, current has #{current_version}"]}

      true ->
        {[], []}
    end
  end

  defp verify_cpu_features(lock_hardware, current) do
    lock_features_list = Map.get(lock_hardware, "cpu_features", [])
    current_features_list = Map.get(current, "cpu_features", [])
    critical_list = ["avx512f"]

    lock_features = MapSet.new(lock_features_list)
    current_features = MapSet.new(current_features_list)
    critical_features = MapSet.new(critical_list)

    missing_critical =
      lock_features
      |> MapSet.intersection(critical_features)
      |> MapSet.difference(current_features)
      |> MapSet.to_list()

    missing_optional =
      lock_features
      |> MapSet.difference(critical_features)
      |> MapSet.difference(current_features)
      |> MapSet.to_list()

    errors =
      if missing_critical != [] do
        ["Missing critical CPU features: #{Enum.join(missing_critical, ", ")}"]
      else
        []
      end

    warnings =
      if missing_optional != [] do
        ["Missing optional CPU features: #{Enum.join(missing_optional, ", ")}"]
      else
        []
      end

    {errors, warnings}
  end

  defp parse_platform(platform_string) when is_binary(platform_string) do
    case String.split(platform_string, "-", parts: 2) do
      [os, arch] -> [os, arch]
      [os] -> [os, "unknown"]
      _ -> ["unknown", "unknown"]
    end
  end

  defp parse_platform(_), do: ["unknown", "unknown"]

  defp major_version(nil), do: nil

  defp major_version(version) when is_binary(version) do
    case String.split(version, ".") do
      [major | _] -> major
      _ -> version
    end
  end

  defp hardware_module do
    Application.get_env(:snakebridge, :hardware_module, Snakepit.Hardware)
  end
end
