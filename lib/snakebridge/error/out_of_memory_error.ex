defmodule SnakeBridge.Error.OutOfMemoryError do
  @moduledoc """
  GPU out-of-memory error with recovery suggestions.

  Provides detailed information about memory failures including
  device info, memory stats, and actionable suggestions.

  ## Examples

      iex> error = %SnakeBridge.Error.OutOfMemoryError{
      ...>   device: {:cuda, 0},
      ...>   requested_mb: 8192,
      ...>   available_mb: 2048,
      ...>   message: "CUDA out of memory"
      ...> }
      iex> Exception.message(error)
      "GPU Out of Memory on CUDA:0..."

  """

  @type device :: :cpu | {:cuda, non_neg_integer()} | :mps | atom()

  @type t :: %__MODULE__{
          device: device(),
          requested_mb: non_neg_integer() | nil,
          available_mb: non_neg_integer() | nil,
          total_mb: non_neg_integer() | nil,
          message: String.t(),
          suggestions: [String.t()],
          python_traceback: String.t() | nil
        }

  defexception [
    :device,
    :requested_mb,
    :available_mb,
    :total_mb,
    :python_traceback,
    message: "Out of memory",
    suggestions: []
  ]

  @impl Exception
  def message(%__MODULE__{} = error) do
    parts = ["GPU Out of Memory on #{format_device(error.device)}"]

    parts =
      if error.requested_mb || error.available_mb || error.total_mb do
        mem_info = [
          "Memory Info:",
          "  Requested: #{error.requested_mb || "unknown"} MB",
          "  Available: #{error.available_mb || "unknown"} MB",
          "  Total: #{error.total_mb || "unknown"} MB"
        ]

        parts ++ [""] ++ mem_info
      else
        parts
      end

    suggestions =
      (error.suggestions ++ default_suggestions(error.device))
      |> Enum.uniq()
      |> Enum.with_index(1)
      |> Enum.map(fn {s, i} -> "  #{i}. #{s}" end)

    parts = parts ++ ["", "Suggestions:"] ++ suggestions

    parts
    |> Enum.join("\n")
    |> String.trim()
  end

  @doc """
  Creates an OutOfMemoryError error with default suggestions.
  """
  @spec new(device(), keyword()) :: t()
  def new(device, opts \\ []) do
    %__MODULE__{
      device: device,
      requested_mb: Keyword.get(opts, :requested_mb),
      available_mb: Keyword.get(opts, :available_mb),
      total_mb: Keyword.get(opts, :total_mb),
      message: Keyword.get(opts, :message, "Out of memory on #{format_device(device)}"),
      suggestions: Keyword.get(opts, :suggestions, []),
      python_traceback: Keyword.get(opts, :python_traceback)
    }
  end

  defp format_device(:cpu), do: "CPU"
  defp format_device(:mps), do: "Apple MPS"
  defp format_device({:cuda, id}), do: "CUDA:#{id}"
  defp format_device(other), do: inspect(other)

  defp default_suggestions(device) do
    base = [
      "Reduce batch size",
      "Use gradient checkpointing",
      "Enable mixed precision training",
      "Clear cached memory"
    ]

    case device do
      {:cuda, _} -> base ++ ["Move some operations to CPU"]
      :mps -> base ++ ["Move some operations to CPU"]
      _ -> base
    end
  end
end
