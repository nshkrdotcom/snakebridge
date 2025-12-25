defmodule SnakeBridge.Manifest.Reader do
  @moduledoc """
  Safely read manifest files without evaluating code.

  Supports JSON manifests and a restricted literal .exs format
  (maps/lists/tuples/atoms/strings/numbers only).
  """

  alias SnakeBridge.Manifest.SafeParser

  @spec read_file(String.t()) :: {:ok, map()} | {:error, term()}
  def read_file(path) when is_binary(path) do
    case Path.extname(path) do
      ".json" -> read_json(path)
      ".exs" -> SafeParser.parse_file(path)
      ext -> {:error, {:unsupported_manifest_format, ext}}
    end
  end

  @spec read_file!(String.t()) :: map()
  def read_file!(path) when is_binary(path) do
    case read_file(path) do
      {:ok, data} -> data
      {:error, reason} -> raise "Failed to read manifest #{path}: #{inspect(reason)}"
    end
  end

  defp read_json(path) do
    with {:ok, contents} <- File.read(path) do
      Jason.decode(contents)
    end
  end
end
