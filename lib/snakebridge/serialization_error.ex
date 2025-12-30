defmodule SnakeBridge.SerializationError do
  @moduledoc """
  Raised when attempting to encode a value that cannot be serialized for Python.

  SnakeBridge supports encoding:
  - Primitives: `nil`, booleans, integers, floats, strings
  - Collections: lists, maps, tuples, MapSets
  - Special types: atoms, DateTime, Date, Time, SnakeBridge.Bytes
  - References: SnakeBridge.Ref, SnakeBridge.StreamRef
  - Functions: anonymous functions (as callbacks)
  - Special floats: `:infinity`, `:neg_infinity`, `:nan`

  Types that cannot be serialized:
  - PIDs, ports, references
  - Custom structs without serialization support
  - File handles, sockets, other system resources

  ## Resolution

  For unsupported types, you have several options:

  1. **Create a Python object and pass the ref**:

         {:ok, ref} = SnakeBridge.call("module", "create_object", [...])
         SnakeBridge.call("module", "use_object", [ref])

  2. **Convert to a supported type**:

         # Instead of passing a PID
         SnakeBridge.call("module", "fn", [inspect(pid)])
         # Or extract relevant data
         SnakeBridge.call("module", "fn", [pid_to_list(pid)])

  3. **Use explicit bytes for binary data**:

         SnakeBridge.call("module", "fn", [SnakeBridge.bytes(binary)])

  """

  defexception [:message, :value, :type]

  @type t :: %__MODULE__{
          message: String.t(),
          value: term(),
          type: atom() | module()
        }

  @impl true
  def exception(opts) when is_list(opts) do
    value = Keyword.fetch!(opts, :value)
    type = get_type(value)
    message = build_message(value, type)

    %__MODULE__{
      message: message,
      value: value,
      type: type
    }
  end

  @doc """
  Creates a SerializationError from a message string.

  This is used for error messages from the Python side.
  """
  @spec new(String.t() | nil) :: t()
  def new(message \\ nil) do
    %__MODULE__{
      message: message || "Arguments are not JSON-serializable",
      value: nil,
      type: :unknown
    }
  end

  defp get_type(value) when is_pid(value), do: :pid
  defp get_type(value) when is_port(value), do: :port
  defp get_type(value) when is_reference(value), do: :reference
  defp get_type(%{__struct__: struct_name}), do: struct_name
  defp get_type(_), do: :unknown

  defp build_message(value, type) do
    """
    Cannot serialize value of type #{inspect(type)} for Python.

    Value: #{inspect(value, limit: 50, printable_limit: 100)}

    SnakeBridge cannot automatically serialize this type. See the module documentation
    for SnakeBridge.SerializationError for resolution options.
    """
  end
end
