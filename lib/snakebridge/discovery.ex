defmodule SnakeBridge.Discovery do
  @moduledoc """
  Discovery and introspection for Python libraries.

  This module provides functions to discover Python library schemas,
  either through automatic introspection or from cached descriptors.
  """

  alias SnakeBridge.Discovery.Introspector

  @doc """
  Discover a Python module's schema.

  ## Options

    * `:depth` - Discovery depth for submodules (default: 2)
    * `:config_hash` - Config hash for cache validation
    * `:use_cache` - Whether to use cached results (default: true)

  ## Example

      {:ok, schema} = SnakeBridge.Discovery.discover("dspy", depth: 3)
  """
  @spec discover(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def discover(module_path, opts \\ []) do
    Introspector.discover(Introspector, module_path, opts)
  end

  @doc """
  Convert discovered schema to SnakeBridge config.
  """
  @spec schema_to_config(map(), keyword()) :: SnakeBridge.Config.t()
  def schema_to_config(schema, opts \\ []) do
    python_module = Keyword.get(opts, :python_module, "unknown")

    %SnakeBridge.Config{
      python_module: python_module,
      version: Map.get(schema, "library_version", "unknown"),
      classes: convert_classes(Map.get(schema, "classes", %{})),
      functions: convert_functions(Map.get(schema, "functions", %{}))
    }
  end

  defp convert_classes(classes_map) do
    Enum.map(classes_map, fn {_name, descriptor} ->
      %{
        python_path: descriptor.python_path || descriptor["python_path"],
        elixir_module: python_path_to_module(descriptor.python_path || descriptor["python_path"]),
        constructor: %{args: %{}, session_aware: true},
        methods: convert_methods(descriptor.methods || descriptor["methods"] || [])
      }
    end)
  end

  defp convert_methods(methods) when is_list(methods) do
    Enum.map(methods, fn method ->
      name = method.name || method["name"]

      %{
        name: name,
        elixir_name: elixir_name_from_python(name),
        streaming: method.supports_streaming || method["supports_streaming"] || false
      }
    end)
  end

  defp convert_functions(functions_map) do
    Enum.map(functions_map, fn {_name, descriptor} ->
      %{
        python_path: descriptor.python_path || descriptor["python_path"],
        elixir_name: elixir_name_from_python(descriptor.name || descriptor["name"]),
        args: %{}
      }
    end)
  end

  defp python_path_to_module(python_path) when is_binary(python_path) do
    python_path
    |> String.split(".")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(".")
    |> String.to_atom()
  end

  defp elixir_name_from_python("__call__"), do: :call
  defp elixir_name_from_python("__init__"), do: :new
  defp elixir_name_from_python(name), do: String.to_atom(name)
end
