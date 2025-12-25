defmodule SnakeBridge.Runtime do
  @moduledoc """
  Runtime execution layer for SnakeBridge.

  Provides the core integration between Elixir and Python through Snakepit,
  handling argument encoding, result decoding, and error management.

  ## Architecture

  The Runtime module serves as a thin wrapper over Snakepit that:
  1. Encodes Elixir arguments using `SnakeBridge.Types.Encoder`
  2. Executes Python code via `Snakepit.execute/3`
  3. Decodes Python results using `SnakeBridge.Types.Decoder`
  4. Handles errors and converts them to Elixir-friendly formats

  ## Protocol

  The Python side expects calls through the "snakebridge_call" tool with:
  - `module`: Python module path (e.g., "json", "numpy")
  - `function`: Function name to call
  - Additional arguments passed through as-is

  ## Examples

      # Call a Python function
      {:ok, result} = SnakeBridge.Runtime.call("json", "dumps", %{obj: %{a: 1}})

      # With options
      {:ok, result} = SnakeBridge.Runtime.call(
        "numpy",
        "array",
        %{object: [1, 2, 3]},
        timeout: 5000
      )

      # Streaming results
      SnakeBridge.Runtime.stream("requests", "get", %{url: "https://example.com"}, fn chunk ->
        IO.inspect(chunk, label: "Chunk")
      end)

  """

  alias SnakeBridge.Types.{Encoder, Decoder}

  require Logger

  @type module_name :: String.t()
  @type function_name :: String.t()
  @type args :: map()
  @type opts :: keyword()
  @type result :: term()
  @type error :: {:error, term()}

  @doc """
  Calls a Python function and returns the result.

  ## Arguments

  - `module` - Python module path (e.g., "json", "numpy.linalg")
  - `function` - Function name to call
  - `args` - Map of arguments (will be encoded for Python)
  - `opts` - Options keyword list

  ## Options

  - `:timeout` - Request timeout in milliseconds (default: 60000)
  - `:session_id` - Session ID for worker affinity
  - Any other options are passed through to Snakepit

  ## Returns

  - `{:ok, result}` - Decoded result from Python
  - `{:error, reason}` - Error tuple with reason

  ## Examples

      iex> SnakeBridge.Runtime.call("json", "dumps", %{obj: %{hello: "world"}})
      {:ok, "{\\"hello\\": \\"world\\"}"}

      iex> SnakeBridge.Runtime.call("math", "sqrt", %{x: 16})
      {:ok, 4.0}

  """
  @spec call(module_name(), function_name(), args(), opts()) :: {:ok, result()} | error()
  def call(module, function, args \\ %{}, opts \\ []) do
    # Encode arguments
    encoded_args = encode_args(args)

    # Build the call payload
    payload =
      %{
        "module" => module,
        "function" => function
      }
      |> Map.merge(encoded_args)

    # Extract options
    timeout = Keyword.get(opts, :timeout, 60_000)
    snakepit_opts = build_snakepit_opts(opts, timeout)

    # Execute via Snakepit
    start_time = System.monotonic_time()

    result =
      case Snakepit.execute("snakebridge_call", payload, snakepit_opts) do
        {:ok, response} ->
          handle_response(response)

        {:error, %Snakepit.Error{} = error} ->
          {:error, format_snakepit_error(error)}
      end

    # Emit telemetry
    duration = System.monotonic_time() - start_time
    emit_telemetry(:call, duration, module, function, result)

    result
  end

  @doc """
  Calls a Python function with streaming results.

  The callback function will be invoked for each chunk of data received
  from the Python side.

  ## Arguments

  - `module` - Python module path
  - `function` - Function name to call
  - `args` - Map of arguments
  - `callback` - Function to call for each chunk: `(chunk -> any())`
  - `opts` - Options keyword list

  ## Options

  - `:timeout` - Request timeout in milliseconds (default: 300000)
  - `:session_id` - Session ID for worker affinity
  - Any other options are passed through to Snakepit

  ## Returns

  - `:ok` - Streaming completed successfully
  - `{:error, reason}` - Error tuple with reason

  ## Examples

      iex> SnakeBridge.Runtime.stream("requests", "iter_content", %{url: "..."}, fn chunk ->
      ...>   IO.puts("Received: \#{inspect(chunk)}")
      ...> end)
      :ok

  """
  @spec stream(module_name(), function_name(), args(), function(), opts()) :: :ok | error()
  def stream(module, function, args \\ %{}, callback, opts \\ [])
      when is_function(callback, 1) do
    # Encode arguments
    encoded_args = encode_args(args)

    # Build the call payload
    payload =
      %{
        "module" => module,
        "function" => function
      }
      |> Map.merge(encoded_args)

    # Extract options
    timeout = Keyword.get(opts, :timeout, 300_000)
    snakepit_opts = build_snakepit_opts(opts, timeout)

    # Wrap callback to decode chunks
    decoding_callback = fn chunk ->
      decoded_chunk = Decoder.decode(chunk)
      callback.(decoded_chunk)
    end

    # Execute via Snakepit streaming
    start_time = System.monotonic_time()

    result =
      case Snakepit.execute_stream("snakebridge_call", payload, decoding_callback, snakepit_opts) do
        :ok ->
          :ok

        {:error, %Snakepit.Error{} = error} ->
          {:error, format_snakepit_error(error)}
      end

    # Emit telemetry
    duration = System.monotonic_time() - start_time
    emit_telemetry(:stream, duration, module, function, result)

    result
  end

  # Private Functions

  @spec encode_args(args()) :: map()
  defp encode_args(args) when is_map(args) do
    Encoder.encode(args)
  end

  defp encode_args(args), do: Encoder.encode(%{args: args})

  @spec build_snakepit_opts(opts(), non_neg_integer()) :: keyword()
  defp build_snakepit_opts(opts, timeout) do
    opts
    |> Keyword.put(:timeout, timeout)
    |> Keyword.put_new(:pool, Snakepit.Pool)
  end

  @spec handle_response(map()) :: {:ok, result()} | error()
  defp handle_response(%{"success" => true, "result" => result}) do
    decoded_result = Decoder.decode(result)
    {:ok, decoded_result}
  end

  defp handle_response(%{"success" => false, "error" => error_msg}) when is_binary(error_msg) do
    {:error, error_msg}
  end

  defp handle_response(%{"success" => false, "error" => error_data}) do
    {:error, Decoder.decode(error_data)}
  end

  defp handle_response(%{"error" => error_msg}) when is_binary(error_msg) do
    {:error, error_msg}
  end

  defp handle_response(response) do
    # Unexpected response format - try to decode anyway
    Logger.warning("Unexpected response format from Python: #{inspect(response)}")
    {:ok, Decoder.decode(response)}
  end

  @spec format_snakepit_error(Snakepit.Error.t()) :: String.t()
  defp format_snakepit_error(%Snakepit.Error{} = error) do
    "Snakepit error (#{error.category}): #{error.message}"
  end

  @spec emit_telemetry(atom(), integer(), module_name(), function_name(), term()) :: :ok
  defp emit_telemetry(call_type, duration, module, function, result) do
    measurements = %{duration: duration}

    metadata = %{
      call_type: call_type,
      module: module,
      function: function,
      success: match?({:ok, _}, result) or result == :ok
    }

    :telemetry.execute(
      [:snakebridge, :runtime, call_type],
      measurements,
      metadata
    )
  end
end
