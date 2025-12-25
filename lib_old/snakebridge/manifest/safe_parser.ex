defmodule SnakeBridge.Manifest.SafeParser do
  @moduledoc """
  Parse a restricted subset of Elixir literals for legacy manifest files.

  This avoids executing code while still allowing simple map/list/tuple
  literals as data.
  """

  @spec parse_file(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_file(path) when is_binary(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, ast} <- Code.string_to_quoted(contents),
         {:ok, value} <- eval(ast) do
      {:ok, value}
    else
      {:error, reason} -> {:error, reason}
      {:error, _line, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  defp eval({:__block__, _, [expr]}), do: eval(expr)

  defp eval({:%{}, _, kvs}) do
    kvs
    |> Enum.map(fn {k, v} ->
      with {:ok, key} <- eval(k),
           {:ok, val} <- eval(v) do
        {:ok, {key, val}}
      end
    end)
    |> collect_map()
  end

  defp eval({:{}, _, elems}) do
    with {:ok, items} <- eval_list(elems) do
      {:ok, List.to_tuple(items)}
    end
  end

  defp eval(list) when is_list(list), do: eval_list(list)

  defp eval({:__aliases__, _, parts}) do
    {:ok, Enum.map_join(parts, ".", &Atom.to_string/1)}
  end

  defp eval(value) when is_atom(value) or is_binary(value) or is_number(value) do
    {:ok, value}
  end

  defp eval(other) do
    {:error, {:unsupported_ast, other}}
  end

  defp eval_list(list) do
    list
    |> Enum.map(&eval/1)
    |> collect_list()
  end

  defp collect_list(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, item}, {:ok, acc} -> {:cont, {:ok, [item | acc]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      {:error, _} = error -> error
    end
  end

  defp collect_map(results) do
    Enum.reduce_while(results, {:ok, %{}}, fn
      {:ok, {key, val}}, {:ok, acc} -> {:cont, {:ok, Map.put(acc, key, val)}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
  end
end
