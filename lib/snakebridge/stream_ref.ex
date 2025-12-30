defmodule SnakeBridge.StreamRef do
  @moduledoc """
  Represents a Python iterator or generator as an Elixir stream.

  Implements the `Enumerable` protocol for lazy iteration.
  """

  defstruct [
    :ref_id,
    :session_id,
    :stream_type,
    :python_module,
    :library,
    exhausted: false
  ]

  @type t :: %__MODULE__{
          ref_id: String.t(),
          session_id: String.t(),
          stream_type: String.t(),
          python_module: String.t(),
          library: String.t(),
          exhausted: boolean()
        }

  @doc """
  Creates a StreamRef from a decoded wire format.
  """
  @spec from_wire_format(map()) :: t()
  def from_wire_format(map) when is_map(map) do
    %__MODULE__{
      ref_id: map["id"],
      session_id: map["session_id"],
      stream_type: map["stream_type"] || "iterator",
      python_module: map["python_module"],
      library: map["library"],
      exhausted: false
    }
  end

  @doc """
  Converts back to wire format for Python calls.
  """
  @spec to_wire_format(t()) :: map()
  def to_wire_format(%__MODULE__{} = ref) do
    %{
      "__type__" => "ref",
      "id" => ref.ref_id,
      "session_id" => ref.session_id,
      "python_module" => ref.python_module,
      "library" => ref.library
    }
  end
end

defimpl Enumerable, for: SnakeBridge.StreamRef do
  alias SnakeBridge.{Runtime, StreamRef}

  def count(%StreamRef{stream_type: "generator"}), do: {:error, __MODULE__}

  def count(%StreamRef{} = ref) do
    case Runtime.stream_len(ref) do
      {:ok, len} when is_integer(len) -> {:ok, len}
      _ -> {:error, __MODULE__}
    end
  end

  def member?(%StreamRef{}, _value), do: {:error, __MODULE__}

  def slice(%StreamRef{}), do: {:error, __MODULE__}

  def reduce(%StreamRef{exhausted: true}, {:cont, acc}, _fun) do
    {:done, acc}
  end

  def reduce(%StreamRef{} = ref, {:cont, acc}, fun) do
    case Runtime.stream_next(ref) do
      {:ok, value} ->
        reduce(ref, fun.(value, acc), fun)

      {:error, :stop_iteration} ->
        {:done, acc}

      {:error, reason} ->
        {:halted, {:error, reason}}
    end
  end

  def reduce(_ref, {:halt, acc}, _fun), do: {:halted, acc}
  def reduce(ref, {:suspend, acc}, fun), do: {:suspended, acc, &reduce(ref, &1, fun)}
end
