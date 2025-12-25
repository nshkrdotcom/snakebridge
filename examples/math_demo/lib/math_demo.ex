defmodule MathDemo do
  @moduledoc """
  Demonstrates SnakeBridge discovery APIs and generated code layout.

  This example shows how to:
  1. Configure SnakeBridge adapters in config/config.exs
  2. Inspect the generated modules under lib/snakebridge_generated
  3. Use discovery helpers like __functions__/0, __classes__/0, and __search__/1

  Runtime Python calls are intentionally omitted from this demo.

  ## Usage

      # Start iex
      $ iex -S mix

      # Explore available functions and classes
      iex> Json.__functions__()
      iex> Math.__functions__()
      iex> Sympy.__functions__()

      # Search for specific functionality
      iex> Math.__search__("sqrt")
      iex> Sympy.__search__("solve")

      # Inspect generated layout
      iex> MathDemo.generated_structure()

      # Print a short discovery summary
      iex> MathDemo.discover()

  """

  @doc """
  Return a summary of the generated adapter layout on disk.

  ## Examples

      iex> MathDemo.generated_structure()
      {:ok, %{root: "...", adapters: %{...}}}

  """
  def generated_structure do
    root = Path.expand("../lib/snakebridge_generated", __DIR__)

    case File.ls(root) do
      {:ok, entries} ->
        adapters =
          entries
          |> Enum.reject(&(&1 == ".gitignore"))
          |> Enum.sort()
          |> Enum.map(fn adapter ->
            module_root = Path.join([root, adapter, adapter])

            files =
              case File.ls(module_root) do
                {:ok, files} -> Enum.sort(files)
                {:error, _} -> []
              end

            {adapter, files}
          end)
          |> Map.new()

        {:ok, %{root: root, adapters: adapters}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Show discovery features of generated modules.
  """
  def discover do
    if Code.ensure_loaded?(Math) do
      IO.puts("=== Math Functions ===")

      Math.__functions__()
      |> Enum.take(10)
      |> Enum.each(fn {name, arity, _mod, doc} ->
        short_doc = String.slice(doc || "", 0, 50)
        IO.puts("  #{name}/#{arity}: #{short_doc}...")
      end)

      IO.puts("\n=== Searching for 'sin' in Math ===")

      Math.__search__("sin")
      |> Enum.each(fn {name, arity, _mod, _doc} ->
        IO.puts("  #{name}/#{arity}")
      end)
    else
      IO.puts("Math module not available. Run `mix compile`.")
    end

    if Code.ensure_loaded?(Json) do
      IO.puts("\n=== Json Classes ===")

      Json.__classes__()
      |> Enum.each(fn entry ->
        {name, mod_ref, doc} = normalize_class_entry(entry)

        short_doc = String.slice(doc || "", 0, 50)

        label =
          if mod_ref do
            "#{inspect(name)} (#{inspect(mod_ref)})"
          else
            inspect(name)
          end

        IO.puts("  #{label}: #{short_doc}...")
      end)
    else
      IO.puts("\nJson module not available. Run `mix compile`.")
    end

    if Code.ensure_loaded?(Sympy) do
      IO.puts("\n=== Sympy Search: solve ===")

      Sympy.__search__("solve")
      |> Enum.take(10)
      |> Enum.each(fn {name, arity, _mod, _doc} ->
        IO.puts("  #{name}/#{arity}")
      end)
    else
      IO.puts("\nSympy module not available. Run `mix compile`.")
    end

    :ok
  end

  defp normalize_class_entry(entry) do
    case entry do
      {name, mod, doc} -> {name, mod, doc}
      {name, doc} -> {name, nil, doc}
      other -> {other, nil, nil}
    end
  end
end
