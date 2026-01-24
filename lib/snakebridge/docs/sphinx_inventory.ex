defmodule SnakeBridge.Docs.SphinxInventory do
  @moduledoc """
  Parser for Sphinx `objects.inv` inventories (version 2).

  This is used to derive a *documented* API surface from published docs without
  requiring access to the Sphinx source tree.
  """

  @type entry :: %{
          required(:name) => String.t(),
          required(:domain_role) => String.t(),
          required(:priority) => non_neg_integer(),
          required(:uri) => String.t(),
          required(:dispname) => String.t()
        }

  @type t :: %{
          required(:project) => String.t() | nil,
          required(:version) => String.t() | nil,
          required(:entries) => [entry()]
        }

  @spec parse(binary()) :: {:ok, t()} | {:error, term()}
  def parse(content) when is_binary(content) do
    with {:ok, header, compressed} <- split_header(content),
         {:ok, decompressed} <- inflate(compressed),
         {:ok, entries} <- parse_entries(decompressed) do
      {:ok,
       %{
         project: Map.get(header, :project),
         version: Map.get(header, :version),
         entries: entries
       }}
    end
  end

  defp split_header(content) do
    with {:ok, line1, rest} <- split_line(content),
         {:ok, line2, rest} <- split_line(rest),
         {:ok, line3, rest} <- split_line(rest),
         {:ok, line4, rest} <- split_line(rest) do
      line1 = trim_cr(line1)
      line2 = trim_cr(line2)
      line3 = trim_cr(line3)
      line4 = trim_cr(line4)

      with :ok <- validate_version_line(line1),
           {:ok, project} <- parse_header_value(line2, "# Project:"),
           {:ok, version} <- parse_header_value(line3, "# Version:"),
           :ok <- validate_compression_line(line4) do
        {:ok, %{project: project, version: version}, rest}
      end
    else
      _ -> {:error, :invalid_header}
    end
  end

  defp trim_cr(line) when is_binary(line), do: String.trim_trailing(line, "\r")

  defp split_line(binary) when is_binary(binary) do
    case :binary.match(binary, "\n") do
      {idx, 1} ->
        line = binary_part(binary, 0, idx)
        rest = binary_part(binary, idx + 1, byte_size(binary) - idx - 1)
        {:ok, line, rest}

      :nomatch ->
        :error
    end
  end

  defp validate_version_line("# Sphinx inventory version 2"), do: :ok
  defp validate_version_line(_), do: {:error, :unsupported_inventory_version}

  defp validate_compression_line("# The remainder of this file is compressed using zlib."),
    do: :ok

  defp validate_compression_line(_), do: {:error, :unsupported_inventory_compression}

  defp parse_header_value(line, prefix) do
    if String.starts_with?(line, prefix) do
      {:ok, String.trim(String.replace_prefix(line, prefix, ""))}
    else
      {:ok, nil}
    end
  end

  defp inflate(data) when is_binary(data) do
    {:ok, :zlib.uncompress(data)}
  rescue
    _ -> {:error, :zlib_uncompress_failed}
  end

  defp parse_entries(decompressed) when is_binary(decompressed) do
    lines =
      decompressed
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    {:ok,
     Enum.flat_map(lines, fn line ->
       case parse_entry_line(line) do
         {:ok, entry} -> [entry]
         {:error, _} -> []
       end
     end)}
  end

  defp parse_entry_line(line) do
    # Format (v2):
    #   name domain:role priority uri dispname
    # `uri` can include a `$` placeholder for `name`.
    case Regex.run(~r/^(.+?)\s+([\w:]+)\s+(\d+)\s+(\S+)\s+(.*)$/, line) do
      [_, name, domain_role, priority, uri, dispname] ->
        uri = String.replace(uri, "$", name)
        dispname = if dispname == "-", do: name, else: dispname

        {:ok,
         %{
           name: name,
           domain_role: domain_role,
           priority: String.to_integer(priority),
           uri: uri,
           dispname: dispname
         }}

      _ ->
        {:error, :invalid_entry}
    end
  end
end
