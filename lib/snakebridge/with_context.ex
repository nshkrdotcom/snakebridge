defmodule SnakeBridge.WithContext do
  @moduledoc """
  Provides Python context manager support via `with_python/2` macro.

  Ensures `__exit__` is always called, even on exception.

  ## Example

      SnakeBridge.with_python(file_ref) do
        SnakeBridge.Dynamic.call(file_ref, :read, [])
      end
  """

  alias SnakeBridge.Runtime

  @doc """
  Executes a block with a Python context manager.

  Calls `__enter__` before the block and guarantees `__exit__` after,
  even if an exception occurs.
  """
  defmacro with_python(ref, do: block) do
    quote do
      ref = unquote(ref)

      case SnakeBridge.WithContext.call_enter(ref) do
        {:ok, context_value} ->
          var!(context) = context_value
          _ = var!(context)
          SnakeBridge.WithContext.execute_with_exit(ref, fn -> unquote(block) end)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc false
  def execute_with_exit(ref, fun) when is_function(fun, 0) do
    outcome =
      try do
        {:ok, fun.()}
      rescue
        exception ->
          {:exception, exception, __STACKTRACE__}
      end

    case outcome do
      {:ok, result} ->
        call_exit(ref, nil)
        result

      {:exception, exception, stacktrace} ->
        call_exit(ref, exception)
        reraise exception, stacktrace
    end
  end

  @doc """
  Calls __enter__ on a Python context manager.
  """
  @spec call_enter(SnakeBridge.Ref.t() | map(), keyword()) :: {:ok, term()} | {:error, term()}
  def call_enter(ref, opts \\ []) do
    Runtime.call_method(ref, :__enter__, [], opts)
  end

  @doc """
  Calls __exit__ on a Python context manager.
  """
  @spec call_exit(SnakeBridge.Ref.t() | map(), Exception.t() | nil, keyword()) ::
          {:ok, term()} | {:error, term()}
  def call_exit(ref, exception, opts \\ []) do
    {exc_type, exc_value, exc_tb} =
      if exception do
        {
          to_string(exception.__struct__),
          Exception.message(exception),
          nil
        }
      else
        {nil, nil, nil}
      end

    Runtime.call_method(ref, :__exit__, [exc_type, exc_value, exc_tb], opts)
  end

  @doc false
  def build_enter_payload(ref) do
    wire_ref = SnakeBridge.Ref.to_wire_format(ref)

    %{
      "call_type" => "method",
      "instance" => wire_ref,
      "method" => "__enter__",
      "args" => []
    }
  end

  @doc false
  def build_exit_payload(ref, exception) do
    {exc_type, exc_value, exc_tb} =
      if exception do
        {to_string(exception.__struct__), Exception.message(exception), nil}
      else
        {nil, nil, nil}
      end

    wire_ref = SnakeBridge.Ref.to_wire_format(ref)

    %{
      "call_type" => "method",
      "instance" => wire_ref,
      "method" => "__exit__",
      "args" => [exc_type, exc_value, exc_tb]
    }
  end
end
