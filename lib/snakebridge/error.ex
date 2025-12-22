defmodule SnakeBridge.Error do
  @moduledoc """
  Structured error representation for SnakeBridge operations.

  Provides error classification based on Python exception types,
  with support for tracebacks and additional context.

  ## Error Types

  Common Python error types are mapped to atoms:
  - `:value_error` - ValueError
  - `:type_error` - TypeError
  - `:import_error` - ImportError
  - `:attribute_error` - AttributeError
  - `:key_error` - KeyError
  - `:index_error` - IndexError
  - `:runtime_error` - RuntimeError
  - `:module_not_found_error` - ModuleNotFoundError
  - `:json_decode_error` - JSONDecodeError
  - `:timeout` - Operation timed out
  - `:snakepit_unavailable` - Snakepit was not running when a call was attempted
  - `:unknown` - Unclassified error

  ## Examples

      # Create from Python error response
      error = SnakeBridge.Error.new(%{
        "success" => false,
        "error" => "ValueError: invalid input",
        "traceback" => "..."
      })
      #=> %SnakeBridge.Error{type: :value_error, ...}

      # Create timeout error
      error = SnakeBridge.Error.from_timeout(5000)
      #=> %SnakeBridge.Error{type: :timeout, ...}
  """

  @type error_type ::
          :value_error
          | :type_error
          | :import_error
          | :attribute_error
          | :key_error
          | :index_error
          | :runtime_error
          | :module_not_found_error
          | :json_decode_error
          | :snakepit_unavailable
          | :timeout
          | :unknown

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          python_traceback: String.t() | nil,
          details: map() | nil
        }

  defexception [:type, :message, :python_traceback, :details]

  # Error patterns as string matches for classification
  @error_type_strings %{
    "ValueError" => :value_error,
    "TypeError" => :type_error,
    "ImportError" => :import_error,
    "AttributeError" => :attribute_error,
    "KeyError" => :key_error,
    "IndexError" => :index_error,
    "RuntimeError" => :runtime_error,
    "ModuleNotFoundError" => :module_not_found_error,
    "JSONDecodeError" => :json_decode_error
  }

  @doc """
  Create a new Error from a Python error response.

  Accepts either a map with `"error"` and optional `"traceback"` keys,
  or a plain string error message.

  ## Examples

      iex> SnakeBridge.Error.new(%{"success" => false, "error" => "ValueError: bad"})
      %SnakeBridge.Error{type: :value_error, message: "ValueError: bad"}

      iex> SnakeBridge.Error.new("Something went wrong")
      %SnakeBridge.Error{type: :unknown, message: "Something went wrong"}
  """
  @spec new(map() | String.t()) :: t()
  def new(%{error: message} = response) when is_binary(message) do
    response
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> new()
  end

  def new(%{"error" => message} = response) when is_binary(message) do
    type =
      case response do
        %{"error_type" => type_str} when is_binary(type_str) -> classify_error(type_str)
        _ -> classify_error(message)
      end

    details =
      response
      |> Map.drop(["success", "error", "traceback"])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
      |> case do
        map when map_size(map) == 0 -> nil
        map -> map
      end

    %__MODULE__{
      type: type,
      message: message,
      python_traceback: Map.get(response, "traceback"),
      details: details
    }
  end

  def new(message) when is_binary(message) do
    %__MODULE__{
      type: classify_error(message),
      message: message,
      python_traceback: nil,
      details: nil
    }
  end

  @doc """
  Create a timeout error.

  ## Examples

      iex> SnakeBridge.Error.from_timeout(5000)
      %SnakeBridge.Error{type: :timeout, message: "Operation timed out after 5000ms"}
  """
  @spec from_timeout(non_neg_integer()) :: t()
  def from_timeout(timeout_ms) do
    %__MODULE__{
      type: :timeout,
      message: "Operation timed out after #{timeout_ms}ms",
      python_traceback: nil,
      details: %{timeout_ms: timeout_ms}
    }
  end

  @doc """
  Classify an error message into an error type.
  """
  @spec classify_error(String.t()) :: error_type()
  def classify_error(message) when is_binary(message) do
    Enum.find_value(@error_type_strings, :unknown, fn {error_string, type} ->
      if String.contains?(message, error_string), do: type
    end)
  end

  # Exception callback
  @impl true
  def message(%__MODULE__{type: type, message: msg}) do
    "[#{type}] #{msg}"
  end
end
