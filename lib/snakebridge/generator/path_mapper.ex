defmodule SnakeBridge.Generator.PathMapper do
  @moduledoc """
  Maps Python module paths to Elixir file paths for split layout generation.

  This module provides deterministic path mapping from Python module paths
  to Elixir source file paths, mirroring Python's package structure.

  ## Convention

  - Package/submodule directories use `__init__.ex` (like Python's `__init__.py`)
  - Class modules use `lowercase_name.ex` files
  - All paths are lowercase with underscores

  ## Examples

      iex> PathMapper.module_to_path("dspy", "lib/gen")
      "lib/gen/dspy/__init__.ex"

      iex> PathMapper.module_to_path("dspy.predict", "lib/gen")
      "lib/gen/dspy/predict/__init__.ex"

      iex> PathMapper.class_file_path("dspy.predict", "RLM", "lib/gen")
      "lib/gen/dspy/predict/rlm.ex"

  """

  @doc """
  Computes file path for a Python module's functions.

  By default, modules are treated as packages and get `__init__.ex`.
  Use `type: :leaf` for leaf modules that should get direct `.ex` files.

  ## Parameters

    * `python_module` - The Python module path (e.g., "dspy.predict")
    * `base_dir` - Base directory for generated files
    * `type` - `:package` (default) or `:leaf`

  ## Examples

      iex> module_to_path("dspy", "lib/gen")
      "lib/gen/dspy/__init__.ex"

      iex> module_to_path("dspy.predict.rlm", "lib/gen", :leaf)
      "lib/gen/dspy/predict/rlm.ex"

  """
  @spec module_to_path(String.t(), String.t(), :package | :leaf) :: String.t()
  def module_to_path(python_module, base_dir, type \\ :package)

  def module_to_path(python_module, base_dir, :package) do
    dir = module_to_dir(python_module, base_dir)
    Path.join(dir, "__init__.ex")
  end

  def module_to_path(python_module, base_dir, :leaf) do
    parts = String.split(python_module, ".")
    {parent_parts, [leaf]} = Enum.split(parts, -1)
    parent_dir = parts_to_dir(parent_parts, base_dir)
    file_name = Macro.underscore(leaf) <> ".ex"
    Path.join(parent_dir, file_name)
  end

  @doc """
  Returns the directory path for a Python module.

  ## Examples

      iex> module_to_dir("dspy", "lib/gen")
      "lib/gen/dspy"

      iex> module_to_dir("dspy.predict", "lib/gen")
      "lib/gen/dspy/predict"

  """
  @spec module_to_dir(String.t(), String.t()) :: String.t()
  def module_to_dir(python_module, base_dir) do
    parts = String.split(python_module, ".")
    parts_to_dir(parts, base_dir)
  end

  defp parts_to_dir([], base_dir), do: String.trim_trailing(base_dir, "/")

  defp parts_to_dir(parts, base_dir) do
    base = String.trim_trailing(base_dir, "/")
    path_parts = Enum.map(parts, &Macro.underscore/1)
    Path.join([base | path_parts])
  end

  @doc """
  Returns all ancestor module paths for a given Python module.

  ## Examples

      iex> ancestor_modules("dspy")
      []

      iex> ancestor_modules("dspy.predict")
      ["dspy"]

      iex> ancestor_modules("dspy.predict.chain.rlm")
      ["dspy", "dspy.predict", "dspy.predict.chain"]

  """
  @spec ancestor_modules(String.t()) :: [String.t()]
  def ancestor_modules(python_module) do
    parts = String.split(python_module, ".")

    parts
    |> Enum.scan([], fn part, acc -> acc ++ [part] end)
    |> Enum.drop(-1)
    |> Enum.map(&Enum.join(&1, "."))
  end

  @doc """
  Converts a Python module path to an Elixir module atom.

  ## Parameters

    * `python_module` - The Python module path
    * `library_module` - The base Elixir module for the library

  ## Examples

      iex> python_module_to_elixir_module("dspy", Dspy)
      Dspy

      iex> python_module_to_elixir_module("dspy.predict", Dspy)
      Dspy.Predict

  """
  @spec python_module_to_elixir_module(String.t(), module()) :: module()
  def python_module_to_elixir_module(python_module, library_module) do
    library_python = library_module |> Module.split() |> Enum.map(&Macro.underscore/1)
    python_parts = String.split(python_module, ".")

    # Find how many parts match the library base
    library_base_count = length(library_python)

    extra_parts =
      python_parts
      |> Enum.drop(library_base_count)
      |> Enum.map(&Macro.camelize/1)

    if extra_parts == [] do
      library_module
    else
      library_module
      |> Module.split()
      |> Kernel.++(extra_parts)
      |> Module.concat()
    end
  end

  @doc """
  Computes the file path for a class module.

  Classes are placed as direct `.ex` files named after the class.

  ## Examples

      iex> class_file_path("dspy.predict", "RLM", "lib/gen")
      "lib/gen/dspy/predict/rlm.ex"

  """
  @spec class_file_path(String.t(), String.t(), String.t()) :: String.t()
  def class_file_path(python_module, class_name, base_dir) do
    # Classes are placed in the python_module's directory, named after the class
    # e.g., class_file_path("dspy.predict", "RLM", "lib/gen") -> "lib/gen/dspy/predict/rlm.ex"
    dir = module_to_dir(python_module, base_dir)
    file_name = Macro.underscore(class_name) <> ".ex"
    Path.join(dir, file_name)
  end

  @doc """
  Computes all file paths needed for a library's functions and classes.

  Returns a tuple of `{module_files, class_files}`. Module files are generated
  for the library root and any python modules that have functions or classes.

  ## Parameters

    * `library_python_name` - The library's Python module name
    * `functions` - List of function info maps with "python_module" key
    * `classes` - List of class info maps with "python_module" and "name" keys
    * `base_dir` - Base directory for generated files

  """
  @spec all_files_for_library(String.t(), [map()], [map()], String.t()) ::
          {[String.t()], [String.t()]}
  def all_files_for_library(library_python_name, functions, classes, base_dir) do
    # Collect all python modules that need files
    function_modules =
      functions
      |> Enum.map(&(&1["python_module"] || library_python_name))
      |> Enum.uniq()

    class_modules =
      classes
      |> Enum.map(&(&1["python_module"] || library_python_name))
      |> Enum.reject(&is_nil/1)

    all_modules =
      [library_python_name | function_modules ++ class_modules]
      |> Enum.uniq()
      |> Enum.sort()

    module_files = Enum.map(all_modules, &module_to_path(&1, base_dir))

    class_files =
      classes
      |> Enum.map(fn class ->
        python_mod = class["python_module"] || library_python_name
        class_name = class["name"] || class["class"] || "Class"
        class_file_path(python_mod, class_name, base_dir)
      end)
      |> Enum.uniq()

    {module_files, class_files}
  end
end
