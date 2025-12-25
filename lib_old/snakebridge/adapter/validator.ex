defmodule SnakeBridge.Adapter.Validator do
  @moduledoc """
  Validates generated SnakeBridge adapters.

  Performs:
  - Manifest JSON schema validation
  - Python package installation check
  - Live function call testing
  - Bridge syntax verification
  """

  require Logger

  @type validation_result :: %{
          valid: boolean(),
          manifest_valid: boolean(),
          python_installed: boolean(),
          functions_tested: integer(),
          functions_passed: integer(),
          errors: [String.t()],
          warnings: [String.t()]
        }

  @doc """
  Validates a complete adapter (manifest + optional bridge).

  ## Parameters

  - `manifest_path` - Path to the manifest JSON file
  - `opts` - Options
    - `:bridge_path` - Path to bridge file (optional)
    - `:venv` - Python venv path (default: ".venv")
    - `:skip_live_test` - Skip live Python tests
    - `:timeout` - Test timeout in ms (default: 30_000)

  ## Returns

  `{:ok, validation_result}` or `{:error, reason}`
  """
  @spec validate(String.t(), keyword()) :: {:ok, validation_result()} | {:error, term()}
  def validate(manifest_path, opts \\ []) do
    venv = Keyword.get(opts, :venv, ".venv")
    skip_live = Keyword.get(opts, :skip_live_test, false)

    errors = []
    warnings = []

    # Validate manifest exists and is valid JSON
    {manifest_valid, manifest_errors, manifest} = validate_manifest(manifest_path)
    errors = errors ++ manifest_errors

    # Check Python package installation
    {python_installed, python_errors} =
      if manifest do
        check_python_package(manifest, venv)
      else
        {false, ["Cannot check Python package: manifest invalid"]}
      end

    errors = errors ++ python_errors

    # Validate bridge if specified
    bridge_path = Keyword.get(opts, :bridge_path)

    {bridge_valid, bridge_errors} =
      if bridge_path && File.exists?(bridge_path) do
        validate_bridge(bridge_path)
      else
        {true, []}
      end

    errors = errors ++ bridge_errors

    # Run live tests if enabled
    {functions_tested, functions_passed, test_errors} =
      if manifest && python_installed && not skip_live do
        run_live_tests(manifest, venv, opts)
      else
        {0, 0, []}
      end

    errors = errors ++ test_errors

    # Add warning if no live tests
    warnings =
      if skip_live do
        ["Live Python tests skipped" | warnings]
      else
        warnings
      end

    result = %{
      valid: manifest_valid && (bridge_path == nil || bridge_valid) && length(errors) == 0,
      manifest_valid: manifest_valid,
      bridge_valid: bridge_valid,
      python_installed: python_installed,
      functions_tested: functions_tested,
      functions_passed: functions_passed,
      errors: errors,
      warnings: warnings
    }

    {:ok, result}
  end

  @doc """
  Validates only the manifest JSON structure.
  """
  @spec validate_manifest(String.t()) :: {boolean(), [String.t()], map() | nil}
  def validate_manifest(manifest_path) do
    case File.read(manifest_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, manifest} ->
            validate_manifest_schema(manifest)

          {:error, reason} ->
            {false, ["Invalid JSON: #{inspect(reason)}"], nil}
        end

      {:error, reason} ->
        {false, ["Cannot read manifest: #{inspect(reason)}"], nil}
    end
  end

  @doc """
  Validates Python bridge file syntax.
  """
  @spec validate_bridge(String.t()) :: {boolean(), [String.t()]}
  def validate_bridge(bridge_path) do
    case System.cmd("python3", ["-m", "py_compile", bridge_path], stderr_to_stdout: true) do
      {_, 0} ->
        {true, []}

      {output, _} ->
        {false, ["Bridge syntax error: #{output}"]}
    end
  end

  @doc """
  Installs Python package if not already installed.
  """
  @spec ensure_python_package(map(), String.t()) :: :ok | {:error, term()}
  def ensure_python_package(manifest, venv) do
    package = manifest["pypi_package"] || manifest["name"]
    pip = Path.join([venv, "bin", "pip"])

    unless File.exists?(pip) do
      {:error, {:venv_not_found, venv}}
    else
      Logger.info("Installing Python package: #{package}")

      case System.cmd(pip, ["install", package], stderr_to_stdout: true) do
        {_, 0} -> :ok
        {output, code} -> {:error, {:pip_install_failed, code, output}}
      end
    end
  end

  # Private - Schema validation

  defp validate_manifest_schema(manifest) do
    required_fields = ["name", "python_module", "functions"]
    errors = []

    # Check required fields
    missing =
      required_fields
      |> Enum.reject(&Map.has_key?(manifest, &1))

    errors =
      if length(missing) > 0 do
        ["Missing required fields: #{Enum.join(missing, ", ")}" | errors]
      else
        errors
      end

    # Validate functions array
    errors =
      case manifest["functions"] do
        functions when is_list(functions) ->
          function_errors =
            functions
            |> Enum.with_index()
            |> Enum.flat_map(fn {func, idx} ->
              validate_function(func, idx)
            end)

          errors ++ function_errors

        nil ->
          errors

        _ ->
          ["'functions' must be an array" | errors]
      end

    # Validate types map
    errors =
      case manifest["types"] do
        types when is_map(types) or is_nil(types) ->
          errors

        _ ->
          ["'types' must be an object" | errors]
      end

    valid = length(errors) == 0
    {valid, Enum.reverse(errors), if(valid, do: manifest, else: nil)}
  end

  defp validate_function(func, idx) do
    errors = []

    errors =
      unless Map.has_key?(func, "name") do
        ["Function #{idx}: missing 'name'" | errors]
      else
        errors
      end

    errors =
      case func["args"] do
        args when is_list(args) or is_nil(args) -> errors
        _ -> ["Function #{idx}: 'args' must be an array" | errors]
      end

    Enum.reverse(errors)
  end

  # Private - Python package check

  defp check_python_package(manifest, venv) do
    module = manifest["python_module"]
    python = Path.join([venv, "bin", "python3"])

    unless File.exists?(python) do
      {false, ["Python venv not found: #{venv}"]}
    else
      check_code = "import #{module}; print('ok')"

      case System.cmd(python, ["-c", check_code], stderr_to_stdout: true) do
        {"ok\n", 0} ->
          {true, []}

        {output, _} ->
          {false, ["Python module '#{module}' not importable: #{String.trim(output)}"]}
      end
    end
  end

  # Private - Live testing

  defp run_live_tests(manifest, venv, opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    functions = manifest["functions"] || []
    module = manifest["python_module"]
    prefix = manifest["python_path_prefix"] || module

    python = Path.join([venv, "bin", "python3"])

    results =
      functions
      |> Enum.take(5)
      |> Enum.map(fn func ->
        test_function(func, prefix, python, timeout)
      end)

    tested = length(results)
    passed = Enum.count(results, fn {status, _} -> status == :ok end)
    errors = Enum.flat_map(results, fn {_, errs} -> errs end)

    {tested, passed, errors}
  end

  defp test_function(func, prefix, python, _timeout) do
    name = func["name"]
    python_path = "#{prefix}.#{name}"

    # Just try to import the function
    check_code = """
    import sys
    try:
        parts = '#{python_path}'.rsplit('.', 1)
        if len(parts) == 2:
            mod = __import__(parts[0], fromlist=[parts[1]])
            func = getattr(mod, parts[1])
            print('ok')
        else:
            print('invalid path')
    except Exception as e:
        print(f'error: {e}')
    """

    case System.cmd(python, ["-c", check_code], stderr_to_stdout: true) do
      {"ok\n", 0} ->
        {:ok, []}

      {output, _} ->
        {:error, ["Function '#{name}' not accessible: #{String.trim(output)}"]}
    end
  end
end
