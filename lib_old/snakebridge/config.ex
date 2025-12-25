defmodule SnakeBridge.Config do
  @moduledoc """
  Configuration schema for SnakeBridge integrations.

  Defines the structure for declarative Python library integration configs.

  ## Example

      config = %SnakeBridge.Config{
        python_module: "sympy",
        version: "1.13.0",
        introspection: %{
          enabled: true,
          cache_path: "priv/snakebridge/schemas/sympy.json"
        },
        classes: [
          %{
            python_path: "sympy.Symbol",
            elixir_module: Sympy.Symbol,
            constructor: %{args: %{name: {:required, :string}}},
            methods: [%{name: "subs", elixir_name: :subs}]
          }
        ]
      }

      {:ok, validated} = SnakeBridge.Config.validate(config)

  ## Legacy Fields

  The following fields are retained for backward compatibility but are not
  currently enforced by the runtime: `grpc`, `bidirectional_tools`,
  `caching`, `telemetry`, `mixins`, `extends`.
  """

  defstruct python_module: nil,
            version: nil,
            description: nil,
            introspection: %{
              enabled: true,
              cache_path: nil,
              discovery_depth: 2,
              submodules: [],
              exclude_patterns: []
            },
            classes: [],
            functions: [],
            bidirectional_tools: %{
              enabled: false,
              export_to_python: []
            },
            grpc: %{
              enabled: true,
              service_name: nil,
              streaming_methods: [],
              max_message_size: 4_194_304
            },
            caching: %{
              enabled: false,
              ttl: 3600,
              cache_pure_functions: true
            },
            telemetry: %{
              enabled: true,
              prefix: [],
              metrics: ["duration", "count", "errors"]
            },
            mixins: [],
            extends: nil,
            timeout: nil,
            compilation_mode: :auto

  @type t :: %__MODULE__{
          python_module: String.t() | nil,
          version: String.t() | nil,
          description: String.t() | nil,
          introspection: map(),
          classes: [map()],
          functions: [map()],
          bidirectional_tools: map(),
          grpc: map(),
          caching: map(),
          telemetry: map(),
          mixins: [map()],
          extends: t() | nil,
          timeout: non_neg_integer() | nil,
          compilation_mode: :auto | :compile_time | :runtime
        }

  @doc """
  Validate a configuration.

  Returns `{:ok, config}` if valid, or `{:error, errors}` with a list of error messages.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, [String.t()]}
  def validate(%__MODULE__{python_module: nil}) do
    {:error, ["python_module is required"]}
  end

  def validate(%__MODULE__{python_module: ""}) do
    {:error, ["python_module cannot be empty"]}
  end

  def validate(%__MODULE__{introspection: introspection} = config) do
    errors = []

    # Validate discovery_depth
    errors =
      if Map.get(introspection, :discovery_depth, 2) < 0 do
        ["discovery_depth must be non-negative" | errors]
      else
        errors
      end

    # Validate classes
    errors =
      Enum.reduce(config.classes, errors, fn class, acc ->
        validate_class(class) ++ acc
      end)

    if Enum.empty?(errors) do
      {:ok, config}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  defp validate_class(class) do
    errors = []

    errors =
      if !Map.has_key?(class, :python_path) || is_nil(class.python_path) do
        ["Class missing required field: python_path" | errors]
      else
        errors
      end

    errors =
      if !Map.has_key?(class, :elixir_module) || is_nil(class.elixir_module) do
        ["Class missing required field: elixir_module" | errors]
      else
        errors
      end

    errors
  end

  @doc """
  Compose configuration with extends and mixins.

  Applies inheritance and mixin patterns to build final configuration.
  """
  @spec compose(t()) :: t()
  def compose(%__MODULE__{extends: nil, mixins: []} = config) do
    config
  end

  def compose(%__MODULE__{extends: parent} = config) when not is_nil(parent) do
    # Merge parent classes with current classes
    merged_classes = parent.classes ++ config.classes

    %{config | classes: merged_classes, extends: nil}
  end

  def compose(%__MODULE__{mixins: mixins} = config) when length(mixins) > 0 do
    # Apply mixins in order, with later mixins taking precedence
    merged =
      Enum.reduce(mixins, config, fn mixin, acc ->
        deep_merge(acc, mixin)
      end)

    %{merged | mixins: []}
  end

  defp deep_merge(config, mixin) when is_map(mixin) do
    # Deep merge mixin into config
    # Config fields take precedence over mixin fields
    Enum.reduce(mixin, config, fn {key, mixin_val}, acc ->
      config_val = Map.get(acc, key)

      merged_val =
        cond do
          is_map(config_val) and is_map(mixin_val) ->
            deep_merge_maps(mixin_val, config_val)

          is_nil(config_val) ->
            mixin_val

          true ->
            config_val
        end

      Map.put(acc, key, merged_val)
    end)
  end

  defp deep_merge_maps(map1, map2) when is_map(map1) and is_map(map2) do
    Map.merge(map1, map2, fn _key, val1, val2 ->
      if is_map(val1) and is_map(val2) do
        deep_merge_maps(val1, val2)
      else
        # Config value takes precedence
        val2
      end
    end)
  end

  @doc """
  Compute content hash of configuration.
  """
  @spec hash(t()) :: String.t()
  def hash(%__MODULE__{} = config) do
    config
    |> Map.from_struct()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Convert config to Elixir code string.
  """
  @spec to_elixir_code(t()) :: String.t()
  def to_elixir_code(%__MODULE__{} = config) do
    """
    %SnakeBridge.Config{
      python_module: #{inspect(config.python_module)},
      version: #{inspect(config.version)},
      classes: #{inspect(config.classes, pretty: true, width: 80)},
      functions: #{inspect(config.functions, pretty: true, width: 80)}
    }
    """
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
    #{Enum.map_join(config.classes, "\n", fn c -> "  - #{Map.get(c, :python_path, "unknown")}" end)}
    functions:
    #{Enum.map_join(config.functions, "\n", fn f -> "  - #{Map.get(f, :python_path, "unknown")}" end)}
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
    struct = struct(__MODULE__, map)
    validate(struct)
  end
end
