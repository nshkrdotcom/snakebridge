defmodule SnakeBridge.Adapter do
  @moduledoc """
  Provides the `use SnakeBridge.Adapter` macro for generated Python adapters.

  When you `use SnakeBridge.Adapter`, it imports the `__python_call__/2` function
  that generated adapters use to call Python functions via Snakepit.

  ## Example

      defmodule MyApp.Math do
        use SnakeBridge.Adapter

        @spec sqrt(number()) :: float()
        def sqrt(x) do
          __python_call__("sqrt", [x])
        end
      end

  The adapter module tracks the Python module name and provides the runtime
  bridge to execute Python functions.
  """

  defmacro __using__(_opts) do
    quote do
      import SnakeBridge.Adapter, only: [__python_call__: 2]

      # Register @python_function as an accumulating attribute for metadata
      # This prevents "set but never used" warnings in generated code
      Module.register_attribute(__MODULE__, :python_function, accumulate: true)

      # Store the Python module name derived from the Elixir module name
      @python_module __MODULE__
                     |> Module.split()
                     |> List.last()
                     |> Macro.underscore()
    end
  end

  @doc """
  Calls a Python function with the given arguments.

  This function is used by generated adapter modules to invoke Python functions
  via the SnakeBridge runtime.

  ## Parameters

    * `func_name` - The Python function name as a string
    * `args` - List of arguments to pass to the function

  ## Returns

  The result of the Python function call, decoded from Python types to Elixir.

  ## Examples

      __python_call__("sqrt", [16])
      # => {:ok, 4.0}

      __python_call__("loads", [~s({"key": "value"})])
      # => {:ok, %{"key" => "value"}}

  """
  @spec __python_call__(String.t(), list()) :: {:ok, any()} | {:error, any()}
  def __python_call__(func_name, args) do
    # Get the calling module to determine the Python module
    {module, _func, _arity} =
      Process.info(self(), :current_stacktrace)
      |> elem(1)
      |> Enum.find(fn {mod, _, _, _} ->
        mod not in [__MODULE__, Process, :erlang]
      end)
      |> case do
        {mod, func, arity, _} -> {mod, func, arity}
        nil -> {nil, nil, nil}
      end

    python_module =
      if module do
        module
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
      else
        "unknown"
      end

    # Build args map from positional args
    args_map =
      args
      |> Enum.with_index()
      |> Enum.into(%{}, fn {arg, idx} -> {"arg#{idx}", arg} end)

    SnakeBridge.Runtime.call(python_module, func_name, args_map)
  end
end
