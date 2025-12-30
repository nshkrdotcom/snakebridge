defmodule SnakeBridge.Dynamic do
  @moduledoc """
  Dynamic dispatch for calling methods on Python objects without generated code.

  Use this module when:
  - Python returns an object of a class you did not generate bindings for
  - You need to call methods dynamically at runtime
  - You want a no-codegen escape hatch for refs
  """

  alias SnakeBridge.Runtime

  @type ref :: SnakeBridge.Ref.t() | map()
  @type opts :: keyword()

  @doc """
  Calls a method on a Python object reference.
  """
  @spec call(ref(), atom() | String.t(), list(), opts()) ::
          {:ok, term()} | {:error, Snakepit.Error.t()}
  def call(ref, method, args \\ [], opts \\ []) do
    validate_ref!(ref)
    Runtime.call_method(ref, method, args, opts)
  end

  @doc """
  Gets an attribute from a Python object reference.
  """
  @spec get_attr(ref(), atom() | String.t(), opts()) ::
          {:ok, term()} | {:error, Snakepit.Error.t()}
  def get_attr(ref, attr, opts \\ []) do
    validate_ref!(ref)
    Runtime.get_attr(ref, attr, opts)
  end

  @doc """
  Sets an attribute on a Python object reference.
  """
  @spec set_attr(ref(), atom() | String.t(), term(), opts()) ::
          {:ok, term()} | {:error, Snakepit.Error.t()}
  def set_attr(ref, attr, value, opts \\ []) do
    validate_ref!(ref)
    Runtime.set_attr(ref, attr, value, opts)
  end

  @doc """
  Checks if a value is a valid Python reference.
  """
  @spec ref?(term()) :: boolean()
  def ref?(value), do: SnakeBridge.Ref.ref?(value)

  @doc false
  def build_call_payload(ref, method, args) do
    wire_ref = SnakeBridge.Ref.to_wire_format(ref)

    %{
      "call_type" => "method",
      "instance" => wire_ref,
      "method" => to_string(method),
      "args" => args
    }
  end

  defp validate_ref!(ref) do
    unless ref?(ref) do
      raise ArgumentError, "Invalid ref: expected a SnakeBridge ref, got: #{inspect(ref)}"
    end
  end
end
