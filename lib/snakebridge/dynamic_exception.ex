defmodule SnakeBridge.DynamicException do
  @moduledoc """
  Dynamically creates Elixir exception modules from Python exception class names.

  This enables pattern matching on Python exceptions:

      rescue
        e in SnakeBridge.DynamicException.ValueError ->
          handle_value_error(e)
  """

  @exception_cache :snakebridge_exception_cache

  @doc """
  Creates an exception struct from a Python class name and message.
  """
  @spec create(String.t(), String.t() | nil, keyword()) :: Exception.t()
  def create(python_class_name, message, opts \\ []) when is_binary(python_class_name) do
    module = get_or_create_module(python_class_name)

    details =
      opts
      |> Keyword.delete(:python_traceback)
      |> then(fn cleaned -> Keyword.get(cleaned, :details, cleaned) end)

    struct(module,
      message: message || "",
      python_class: python_class_name,
      details: details,
      python_traceback: Keyword.get(opts, :python_traceback)
    )
  end

  @doc """
  Gets or creates an exception module for a Python class name.
  """
  @spec get_or_create_module(String.t()) :: module()
  def get_or_create_module(python_class_name) when is_binary(python_class_name) do
    ensure_cache_exists()
    class_name = sanitize_class_name(python_class_name)
    module_name = Module.concat(__MODULE__, class_name)

    if Code.ensure_loaded?(module_name) do
      :ets.insert(@exception_cache, {module_name, true})
      module_name
    else
      case :ets.lookup(@exception_cache, module_name) do
        [{^module_name, true}] ->
          module_name

        [] ->
          create_exception_module(module_name, python_class_name)
          module_name
      end
    end
  end

  @doc false
  def ensure_cache_exists do
    if :ets.whereis(@exception_cache) == :undefined do
      :ets.new(@exception_cache, [:named_table, :set, :public])
    end
  end

  defp create_exception_module(module_name, python_class_name) do
    unless Code.ensure_loaded?(module_name) do
      Module.create(
        module_name,
        quote do
          @moduledoc """
          Dynamic exception for Python `#{unquote(python_class_name)}`.
          """

          defexception [:message, :python_class, :details, :python_traceback]

          @impl true
          def message(%{message: message}), do: message || ""
        end,
        Macro.Env.location(__ENV__)
      )
    end

    :ets.insert(@exception_cache, {module_name, true})
  end

  defp sanitize_class_name(python_class_name) do
    python_class_name
    |> String.split(".")
    |> List.last()
    |> String.replace(~r/[^A-Za-z0-9_]/, "")
    |> String.split("_", trim: true)
    |> Enum.map_join("", &capitalize_preserve/1)
    |> normalize_name()
  end

  defp normalize_name(""), do: "PythonError"

  defp normalize_name(<<first::utf8, _rest::binary>> = name) when first in ?0..?9 do
    "Py" <> name
  end

  defp normalize_name(name), do: name

  defp capitalize_preserve(<<first::utf8, rest::binary>>) when first in ?a..?z do
    <<first - 32>> <> rest
  end

  defp capitalize_preserve(segment), do: segment
end
