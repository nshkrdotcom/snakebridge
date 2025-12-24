defmodule SnakeBridge do
  @moduledoc """
  Public API for SnakeBridge - Configuration-driven Python library integration for Elixir.

  SnakeBridge enables seamless integration with Python libraries by automatically
  generating type-safe Elixir modules from declarative configurations.

  ## Quick Start

      # Discover a Python library
      {:ok, schema} = SnakeBridge.discover("sympy")

      # Convert to config and generate modules
      config = SnakeBridge.Discovery.schema_to_config(schema, python_module: "sympy")
      {:ok, modules} = SnakeBridge.generate(config)

      # Or do it all in one step
      {:ok, modules} = SnakeBridge.integrate("sympy")

  ## Workflow

  1. **Discover** - Introspect Python library to extract schema
  2. **Configure** - Review and customize generated config
  3. **Generate** - Create type-safe Elixir wrapper modules
  4. **Use** - Call Python code as if it were native Elixir

  See individual function documentation for details.
  """

  alias SnakeBridge.{Discovery, Generator}

  @doc """
  Discover a Python library's schema.

  Introspects the Python library using Snakepit and returns a schema
  containing all classes, methods, and functions.

  ## Parameters

    * `module_path` - Python module to discover (e.g., "sympy", "pylatexenc")
    * `opts` - Discovery options
      * `:depth` - How deep to traverse submodules (default: 2)
      * `:session_id` - Reuse existing Snakepit session
      * `:config_hash` - Cache validation hash

  ## Returns

    * `{:ok, schema}` - Discovered schema map
    * `{:error, reason}` - Discovery failed

  ## Examples

      {:ok, schema} = SnakeBridge.discover("sympy")
      {:ok, schema} = SnakeBridge.discover("pylatexenc", depth: 3)
  """
  @spec discover(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def discover(module_path, opts \\ []) do
    Discovery.discover(module_path, opts)
  end

  @doc """
  Generate Elixir modules from a SnakeBridge configuration.

  Takes a validated SnakeBridge.Config struct and generates corresponding
  Elixir wrapper modules. In development mode, modules are compiled and loaded
  dynamically. In production, use compile-time generation.

  ## Parameters

    * `config` - SnakeBridge.Config struct (must be valid)

  ## Returns

    * `{:ok, modules}` - List of generated module atoms
    * `{:error, reason}` - Generation or validation failed

  ## Examples

      config = %SnakeBridge.Config{python_module: "sympy", ...}
      {:ok, [Sympy.Symbol]} = SnakeBridge.generate(config)
  """
  @spec generate(SnakeBridge.Config.t()) :: {:ok, [module()]} | {:error, term()}
  def generate(config) do
    Generator.generate_all(config)
  end

  @doc """
  Discover and generate in a single step.

  Convenience function that combines discovery and generation. Perfect for
  quick prototyping and interactive development.

  ## Parameters

    * `module_path` - Python module to integrate
    * `opts` - Combined options for both discovery and generation
      * `:depth` - Discovery depth (default: 2)
      * `:return` - What to return: `:modules` (default) or `:full`

  ## Returns

    * `{:ok, modules}` - When `return: :modules` (default)
    * `{:ok, %{config: config, modules: modules}}` - When `return: :full`
    * `{:error, reason}` - Failed at any step

  ## Examples

      # Simple integration
      {:ok, modules} = SnakeBridge.integrate("sympy")

      # Get config too
      {:ok, %{config: config, modules: modules}} =
        SnakeBridge.integrate("sympy", return: :full)
  """
  @spec integrate(String.t(), keyword()) ::
          {:ok, [module()] | map()} | {:error, term()}
  def integrate(module_path, opts \\ []) do
    return_format = Keyword.get(opts, :return, :modules)
    depth = Keyword.get(opts, :depth, 2)

    with {:ok, schema} <- discover(module_path, depth: depth),
         config = Discovery.schema_to_config(schema, python_module: module_path),
         {:ok, modules} <- generate(config) do
      case return_format do
        :modules -> {:ok, modules}
        :full -> {:ok, %{config: config, modules: modules}}
      end
    end
  end
end
