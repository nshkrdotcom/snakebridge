defmodule SnakeBridge.Generator.Introspector do
  @moduledoc """
  Introspects Python libraries to extract their API information.

  This module shells out to a Python script that uses the `inspect` module
  to analyze a Python library and returns structured information about its
  functions, classes, methods, and type signatures.

  ## Example

      iex> SnakeBridge.Generator.Introspector.introspect("math")
      {:ok, %{
        "module" => "math",
        "functions" => [
          %{
            "name" => "sqrt",
            "type" => "function",
            "params" => [%{"name" => "x", "type" => %{"type" => "float"}}],
            "return_type" => %{"type" => "float"},
            "docstring" => "Return the square root of x."
          }
        ],
        "classes" => []
      }}

  """

  require Logger

  @type introspection_result :: %{
          required(String.t()) => String.t() | list(map()) | map(),
          optional(String.t()) => any()
        }

  @doc """
  Introspects a Python library and returns its API information.

  This function shells out to `priv/python/introspect.py` which uses Python's
  inspect module to analyze the specified library.

  ## Parameters

    * `library` - The name of the Python library to introspect (e.g., "math", "json")

  ## Returns

    * `{:ok, introspection}` - Successfully introspected the library
    * `{:error, reason}` - Failed to introspect (library not found, parse error, etc.)

  ## Examples

      iex> SnakeBridge.Generator.Introspector.introspect("json")
      {:ok, %{"module" => "json", "functions" => [...], "classes" => [...]}}

      iex> SnakeBridge.Generator.Introspector.introspect("nonexistent_module")
      {:error, "Failed to import module: No module named 'nonexistent_module'"}

  """
  @spec introspect(String.t()) :: {:ok, introspection_result()} | {:error, term()}
  def introspect(library) when is_binary(library) do
    script_path = get_introspect_script_path()

    case File.exists?(script_path) do
      false ->
        {:error, "Introspection script not found at #{script_path}"}

      true ->
        run_introspection(script_path, library)
    end
  end

  @doc """
  Same as `introspect/1` but raises on error.

  ## Examples

      iex> SnakeBridge.Generator.Introspector.introspect!("json")
      %{"module" => "json", "functions" => [...]}

  """
  @spec introspect!(String.t()) :: introspection_result()
  def introspect!(library) do
    case introspect(library) do
      {:ok, result} -> result
      {:error, reason} -> raise "Introspection failed: #{inspect(reason)}"
    end
  end

  # Private Functions

  @spec get_introspect_script_path() :: String.t()
  defp get_introspect_script_path do
    priv_dir = :code.priv_dir(:snakebridge)

    case priv_dir do
      {:error, :bad_name} ->
        # Fallback for development when running from source
        Path.join([File.cwd!(), "priv", "python", "introspect.py"])

      priv_path when is_list(priv_path) ->
        # :code.priv_dir returns a charlist
        Path.join([to_string(priv_path), "python", "introspect.py"])
    end
  end

  @spec run_introspection(String.t(), String.t()) ::
          {:ok, introspection_result()} | {:error, term()}
  defp run_introspection(script_path, library) do
    # Use python3 explicitly to ensure compatibility
    python_cmd = System.find_executable("python3") || System.find_executable("python")

    unless python_cmd do
      {:error, "Python executable not found in PATH"}
    else
      # Run the introspection script
      # Use --flat for v2.0 format compatibility with SourceWriter
      case System.cmd(python_cmd, [script_path, library, "--flat"], stderr_to_stdout: true) do
        {output, 0} ->
          parse_introspection_output(output)

        {output, exit_code} ->
          Logger.debug("Introspection failed with exit code #{exit_code}: #{output}")
          {:error, "Introspection failed: #{String.trim(output)}"}
      end
    end
  rescue
    error ->
      {:error, "Exception during introspection: #{Exception.message(error)}"}
  end

  @spec parse_introspection_output(String.t()) ::
          {:ok, introspection_result()} | {:error, term()}
  defp parse_introspection_output(output) do
    case Jason.decode(output) do
      {:ok, %{"error" => error_msg}} ->
        {:error, error_msg}

      {:ok, result} when is_map(result) ->
        {:ok, result}

      {:error, %Jason.DecodeError{} = error} ->
        Logger.debug("Failed to parse introspection output: #{output}")
        {:error, "JSON decode error: #{Exception.message(error)}"}
    end
  end
end
