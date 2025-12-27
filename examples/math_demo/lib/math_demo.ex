defmodule MathDemo do
  @moduledoc """
  Demonstrates SnakeBridge v3 discovery APIs and generated layout.

  This example shows how to:
  1. Declare libraries in mix.exs dependency options
  2. Inspect generated modules under lib/snakebridge_generated
  3. Use discovery helpers like __functions__/0, __classes__/0, and __search__/1
  4. Execute runtime calls via Snakepit-backed functions

  ## Usage

      # Start iex
      $ iex -S mix

      # Explore available functions and classes
      iex> Json.__functions__()
      iex> Math.__functions__()

      # Search for specific functionality
      iex> Math.__search__("sq")

      # Inspect generated layout
      iex> MathDemo.generated_structure()

      # Print a short discovery summary
      iex> MathDemo.discover()

      # Run a runtime sample
      iex> MathDemo.compute_sample()

  """

  @doc """
  Return a summary of the generated layout on disk.

  ## Examples

      iex> MathDemo.generated_structure()
      {:ok, %{root: "...", libraries: ["json", "math"]}}

  """
  def generated_structure do
    root = Path.expand("../lib/snakebridge_generated", __DIR__)

    case File.ls(root) do
      {:ok, entries} ->
        files =
          entries
          |> Enum.filter(&String.ends_with?(&1, ".ex"))
          |> Enum.sort()

        libraries = Enum.map(files, &Path.rootname/1)

        {:ok, %{root: root, libraries: libraries, files: files}}

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
      |> Enum.take(5)
      |> Enum.each(fn {name, arity, _mod, doc} ->
        short_doc = String.slice(doc || "", 0, 50)
        IO.puts("  #{name}/#{arity}: #{short_doc}...")
      end)

      IO.puts("\n=== Math Search: sq ===")

      Math.__search__("sq")
      |> Enum.each(fn %{name: name, summary: summary, relevance: relevance} ->
        short_doc = String.slice(summary || "", 0, 50)
        IO.puts("  #{name} (#{Float.round(relevance, 2)}): #{short_doc}...")
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

    :ok
  end

  @doc """
  Execute a few runtime calls to verify the bridge is working.
  """
  def compute_sample do
    if Code.ensure_loaded?(Math) do
      with {:ok, sqrt} <- Math.sqrt(2),
           {:ok, sin} <- Math.sin(1.0),
           {:ok, cos} <- Math.cos(0.0) do
        {:ok, %{sqrt: sqrt, sin: sin, cos: cos}}
      end
    else
      {:error, :math_module_unavailable}
    end
  end

  defp normalize_class_entry(entry) do
    case entry do
      {name, mod, doc} -> {name, mod, doc}
      {name, doc} -> {name, nil, doc}
      other -> {other, nil, nil}
    end
  end
end
