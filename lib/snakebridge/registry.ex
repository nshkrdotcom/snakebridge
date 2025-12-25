defmodule SnakeBridge.Registry do
  @moduledoc """
  Registry system for tracking generated SnakeBridge adapters.

  The registry maintains a record of all generated Python library adapters,
  allowing agents and tools to introspect what libraries are available without
  parsing code.

  ## Registry Format

  The registry stores library information including:

  - Python module name and version
  - Generated Elixir module name
  - Generation timestamp
  - File locations and structure
  - Statistics (function count, class count, etc.)

  ## Usage

      # Register a new library
      SnakeBridge.Registry.register("numpy", %{
        python_module: "numpy",
        python_version: "1.26.0",
        elixir_module: "Numpy",
        generated_at: ~U[2024-12-24 14:00:00Z],
        path: "lib/snakebridge/adapters/numpy/",
        files: ["numpy.ex", "linalg.ex", "_meta.ex"],
        stats: %{functions: 165, classes: 2, submodules: 4}
      })

      # Check if a library is generated
      SnakeBridge.Registry.generated?("numpy")
      # => true

      # Get library information
      SnakeBridge.Registry.get("numpy")
      # => %{python_module: "numpy", ...}

      # List all generated libraries
      SnakeBridge.Registry.list_libraries()
      # => ["json", "numpy", "sympy"]

  ## Persistence

  The registry is automatically persisted to a JSON file at:
  `priv/snakebridge/registry.json`

  Use `save/0` to persist changes and `load/0` to restore from disk.
  """

  use Agent

  require Logger

  @type library_name :: String.t()

  @type registry_entry :: %{
          python_module: String.t(),
          python_version: String.t(),
          elixir_module: String.t(),
          generated_at: DateTime.t(),
          path: String.t(),
          files: [String.t()],
          stats: %{
            functions: non_neg_integer(),
            classes: non_neg_integer(),
            submodules: non_neg_integer()
          }
        }

  @type registry_state :: %{
          optional(library_name()) => registry_entry()
        }

  # Registry version for compatibility tracking
  @registry_version "2.1"

  # Required entry fields for validation
  @required_fields [
    :python_module,
    :python_version,
    :elixir_module,
    :generated_at,
    :path,
    :files,
    :stats
  ]
  @required_stat_fields [:functions, :classes, :submodules]

  ## Client API

  @doc """
  Starts the registry agent.

  This is typically called by the application supervisor.
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    Agent.start_link(fn -> %{} end, Keyword.merge([name: __MODULE__], opts))
  end

  @doc """
  Returns a list of all registered library names, sorted alphabetically.

  ## Examples

      iex> SnakeBridge.Registry.register("numpy", entry)
      :ok
      iex> SnakeBridge.Registry.list_libraries()
      ["numpy"]
  """
  @spec list_libraries() :: [library_name()]
  def list_libraries do
    ensure_started()

    Agent.get(__MODULE__, fn state ->
      state
      |> Map.keys()
      |> Enum.sort()
    end)
  end

  @doc """
  Gets information about a registered library.

  Returns `nil` if the library is not registered.

  ## Examples

      iex> SnakeBridge.Registry.get("numpy")
      %{python_module: "numpy", python_version: "1.26.0", ...}

      iex> SnakeBridge.Registry.get("nonexistent")
      nil
  """
  @spec get(library_name()) :: registry_entry() | nil
  def get(library_name) do
    ensure_started()
    Agent.get(__MODULE__, fn state -> Map.get(state, library_name) end)
  end

  @doc """
  Checks if a library is registered.

  ## Examples

      iex> SnakeBridge.Registry.generated?("numpy")
      true

      iex> SnakeBridge.Registry.generated?("nonexistent")
      false
  """
  @spec generated?(library_name()) :: boolean()
  def generated?(library_name) do
    ensure_started()
    Agent.get(__MODULE__, fn state -> Map.has_key?(state, library_name) end)
  end

  @doc """
  Registers a library in the registry.

  Updates the entry if the library is already registered.

  ## Parameters

    - `library_name` - The library identifier (e.g., "numpy")
    - `entry` - A map containing library information (see module documentation)

  ## Returns

    - `:ok` on success
    - `{:error, reason}` if the entry is invalid

  ## Examples

      iex> entry = %{
      ...>   python_module: "numpy",
      ...>   python_version: "1.26.0",
      ...>   elixir_module: "Numpy",
      ...>   generated_at: ~U[2024-12-24 14:00:00Z],
      ...>   path: "lib/snakebridge/adapters/numpy/",
      ...>   files: ["numpy.ex"],
      ...>   stats: %{functions: 10, classes: 0, submodules: 1}
      ...> }
      iex> SnakeBridge.Registry.register("numpy", entry)
      :ok
  """
  @spec register(library_name(), map()) :: :ok | {:error, String.t()}
  def register(library_name, entry) when is_binary(library_name) and is_map(entry) do
    ensure_started()

    case validate_entry(entry) do
      :ok ->
        Agent.update(__MODULE__, fn state ->
          Map.put(state, library_name, normalize_entry(entry))
        end)

        :ok

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Removes a library from the registry.

  Returns `:ok` even if the library was not registered.

  ## Examples

      iex> SnakeBridge.Registry.unregister("numpy")
      :ok
  """
  @spec unregister(library_name()) :: :ok
  def unregister(library_name) do
    ensure_started()

    Agent.update(__MODULE__, fn state ->
      Map.delete(state, library_name)
    end)

    :ok
  end

  @doc """
  Clears all entries from the registry.

  ## Examples

      iex> SnakeBridge.Registry.clear()
      :ok
  """
  @spec clear() :: :ok
  def clear do
    ensure_started()

    Agent.update(__MODULE__, fn _state -> %{} end)

    :ok
  end

  @doc """
  Saves the registry to the JSON file.

  Creates the parent directory if it doesn't exist.

  ## Returns

    - `:ok` on success
    - `{:error, reason}` if saving fails

  ## Examples

      iex> SnakeBridge.Registry.save()
      :ok
  """
  @spec save() :: :ok | {:error, term()}
  def save do
    ensure_started()

    registry_path = get_registry_path()

    with :ok <- ensure_registry_dir(registry_path),
         {:ok, data} <- build_registry_data(),
         {:ok, json} <- Jason.encode(data, pretty: true),
         :ok <- File.write(registry_path, json) do
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Failed to save registry to #{registry_path}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Loads the registry from the JSON file.

  If the file doesn't exist, initializes an empty registry.

  ## Returns

    - `:ok` on success
    - `{:error, reason}` if loading fails

  ## Examples

      iex> SnakeBridge.Registry.load()
      :ok
  """
  @spec load() :: :ok | {:error, term()}
  def load do
    ensure_started()

    registry_path = get_registry_path()

    case File.read(registry_path) do
      {:ok, content} ->
        with {:ok, data} <- Jason.decode(content),
             {:ok, libraries} <- parse_registry_data(data) do
          Agent.update(__MODULE__, fn _state -> libraries end)
          :ok
        else
          {:error, reason} = error ->
            Logger.error("Failed to parse registry from #{registry_path}: #{inspect(reason)}")
            error
        end

      {:error, :enoent} ->
        # File doesn't exist yet - start with empty registry
        Logger.debug("Registry file not found at #{registry_path}, starting with empty registry")
        :ok

      {:error, reason} = error ->
        Logger.error("Failed to read registry from #{registry_path}: #{inspect(reason)}")
        error
    end
  end

  ## Private Functions

  # Ensures the registry agent is started
  defp ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        # Start the agent if not already started
        {:ok, _pid} = start_link()
        :ok

      _pid ->
        :ok
    end
  end

  # Gets the registry file path from config or default
  defp get_registry_path do
    Application.get_env(:snakebridge, :registry_path) ||
      Path.join([File.cwd!(), "priv", "snakebridge", "registry.json"])
  end

  # Ensures the registry directory exists
  defp ensure_registry_dir(registry_path) do
    registry_path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  # Validates a registry entry has all required fields
  defp validate_entry(entry) do
    # Check required top-level fields
    missing_fields =
      @required_fields
      |> Enum.reject(fn field -> Map.has_key?(entry, field) end)

    cond do
      length(missing_fields) > 0 ->
        {:error, "Missing required fields: #{inspect(missing_fields)}"}

      not is_map(entry.stats) ->
        {:error, "stats must be a map"}

      true ->
        validate_stats(entry.stats)
    end
  end

  # Validates the stats sub-map
  defp validate_stats(stats) do
    missing_stat_fields =
      @required_stat_fields
      |> Enum.reject(fn field -> Map.has_key?(stats, field) end)

    if length(missing_stat_fields) > 0 do
      {:error, "Missing required stat fields: #{inspect(missing_stat_fields)}"}
    else
      :ok
    end
  end

  # Normalizes an entry to ensure consistent structure
  defp normalize_entry(entry) do
    %{
      python_module: entry.python_module,
      python_version: entry.python_version,
      elixir_module: entry.elixir_module,
      generated_at: normalize_datetime(entry.generated_at),
      path: entry.path,
      files: entry.files,
      stats: normalize_stats(entry.stats)
    }
  end

  # Normalizes stats to ensure atoms as keys
  defp normalize_stats(stats) do
    %{
      functions: stats[:functions] || stats["functions"],
      classes: stats[:classes] || stats["classes"],
      submodules: stats[:submodules] || stats["submodules"]
    }
  end

  # Normalizes datetime - accepts DateTime or string
  defp normalize_datetime(%DateTime{} = dt), do: dt

  defp normalize_datetime(string) when is_binary(string) do
    case DateTime.from_iso8601(string) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> raise ArgumentError, "Invalid datetime string: #{string}"
    end
  end

  # Builds the registry data structure for JSON serialization
  defp build_registry_data do
    libraries =
      Agent.get(__MODULE__, fn state ->
        state
        |> Enum.map(fn {name, entry} ->
          {name, serialize_entry(entry)}
        end)
        |> Enum.into(%{})
      end)

    data = %{
      "version" => @registry_version,
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "libraries" => libraries
    }

    {:ok, data}
  end

  # Serializes a registry entry for JSON
  defp serialize_entry(entry) do
    %{
      "python_module" => entry.python_module,
      "python_version" => entry.python_version,
      "elixir_module" => entry.elixir_module,
      "generated_at" => DateTime.to_iso8601(entry.generated_at),
      "path" => entry.path,
      "files" => entry.files,
      "stats" => %{
        "functions" => entry.stats.functions,
        "classes" => entry.stats.classes,
        "submodules" => entry.stats.submodules
      }
    }
  end

  # Parses registry data from JSON
  defp parse_registry_data(%{"libraries" => libraries}) when is_map(libraries) do
    parsed =
      libraries
      |> Enum.map(fn {name, entry} ->
        case deserialize_entry(entry) do
          {:ok, parsed_entry} -> {name, parsed_entry}
          {:error, reason} -> {:error, {name, reason}}
        end
      end)

    # Check for any errors
    errors =
      Enum.filter(parsed, fn
        {:error, _} -> true
        _ -> false
      end)

    if length(errors) > 0 do
      {:error, "Invalid entries: #{inspect(errors)}"}
    else
      {:ok, Enum.into(parsed, %{})}
    end
  end

  defp parse_registry_data(_data) do
    {:error, "Invalid registry format: missing 'libraries' key"}
  end

  # Deserializes a registry entry from JSON
  defp deserialize_entry(entry) when is_map(entry) do
    try do
      {:ok, generated_at, _offset} = DateTime.from_iso8601(entry["generated_at"])

      parsed = %{
        python_module: entry["python_module"],
        python_version: entry["python_version"],
        elixir_module: entry["elixir_module"],
        generated_at: generated_at,
        path: entry["path"],
        files: entry["files"],
        stats: %{
          functions: entry["stats"]["functions"],
          classes: entry["stats"]["classes"],
          submodules: entry["stats"]["submodules"]
        }
      }

      {:ok, parsed}
    rescue
      e ->
        {:error, "Failed to deserialize entry: #{inspect(e)}"}
    end
  end

  defp deserialize_entry(_entry) do
    {:error, "Entry must be a map"}
  end
end
