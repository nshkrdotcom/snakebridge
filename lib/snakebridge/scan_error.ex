defmodule SnakeBridge.ScanError do
  @moduledoc """
  Structured error for scan failures.
  """

  defexception [:failures]

  @type t :: %__MODULE__{failures: list(map())}

  @impl Exception
  def message(%__MODULE__{failures: failures}) do
    failures
    |> Enum.map_join("\n", fn %{path: path, reason: reason} ->
      "  - #{path}: #{inspect(reason)}"
    end)
    |> then(&("Scan failed for #{length(failures)} file(s):\n" <> &1))
  end
end
