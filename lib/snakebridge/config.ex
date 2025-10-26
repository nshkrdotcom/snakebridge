defmodule SnakeBridge.Config do
  @moduledoc """
  Configuration schema for SnakeBridge integrations.

  Defines the structure for declarative Python library integration configs.
  """

  # Placeholder - will be replaced with full Ecto schema implementation
  defstruct python_module: nil,
            version: nil,
            description: nil,
            introspection: %{},
            classes: [],
            functions: [],
            bidirectional_tools: %{},
            grpc: %{},
            caching: %{},
            telemetry: %{},
            mixins: [],
            extends: nil,
            timeout: nil,
            compilation_mode: :auto

  @type t :: %__MODULE__{}

  @doc """
  Validate a configuration.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, [String.t()]}
  def validate(%__MODULE__{python_module: nil}) do
    {:error, ["python_module is required"]}
  end

  def validate(%__MODULE__{} = config) do
    {:ok, config}
  end

  @doc """
  Compute content hash of configuration.
  """
  @spec hash(t()) :: String.t()
  def hash(%__MODULE__{} = config) do
    config
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Compose configuration with extends and mixins.
  """
  @spec compose(t()) :: t()
  def compose(%__MODULE__{} = config) do
    # Placeholder - will implement full composition logic
    config
  end

  @doc """
  Convert config to Elixir code string.
  """
  @spec to_elixir_code(t()) :: String.t()
  def to_elixir_code(%__MODULE__{} = config) do
    "%SnakeBridge.Config{python_module: #{inspect(config.python_module)}}"
  end

  @doc """
  Pretty print configuration.
  """
  @spec pretty_print(t()) :: String.t()
  def pretty_print(%__MODULE__{} = config) do
    """
    python_module: #{config.python_module}
    version: #{config.version}
    classes:
    #{Enum.map_join(config.classes, "\n", fn c -> "  - #{c.python_path || "unknown"}" end)}
    """
  end

  @doc """
  Convert config to map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = config) do
    Map.from_struct(config)
  end

  @doc """
  Create config from map.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map) do
    {:ok, struct(__MODULE__, map)}
  end
end
