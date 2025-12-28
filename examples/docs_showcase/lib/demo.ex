defmodule Demo do
  @moduledoc """
  Documentation Showcase Demo - Shows how Python docstrings are parsed and rendered.

  Run with: mix run -e Demo.run
  """

  alias SnakeBridge.Docs.RstParser
  alias SnakeBridge.Docs.MarkdownConverter
  alias SnakeBridge.Docs.MathRenderer

  def run do
    Snakepit.run_as_script(fn ->
      IO.puts("""
      ╔═══════════════════════════════════════════════════════════╗
      ║         SnakeBridge Documentation Showcase                ║
      ╚═══════════════════════════════════════════════════════════╝

      This demo shows how Python docstrings are parsed and converted
      to Elixir ExDoc-compatible Markdown format.

      """)

      demo_stdlib_modules()
      demo_docstring_styles()
      demo_math_rendering()

      IO.puts("""

      ════════════════════════════════════════════════════════════
      Demo complete! SnakeBridge documentation features:
        - Automatic docstring style detection (Google, NumPy, Sphinx)
        - Parameter and return type extraction
        - Math expression rendering (:math:`...` -> $...$)
        - Python-to-Elixir type conversion
      ════════════════════════════════════════════════════════════
      """)
    end)
    |> case do
      {:error, reason} ->
        IO.puts("Snakepit script failed: #{inspect(reason)}")

      _ ->
        :ok
    end
  end

  # ============================================================================
  # SECTION 1: Standard Library Module Documentation
  # ============================================================================

  defp demo_stdlib_modules do
    IO.puts("─── SECTION 1: Python Standard Library Docs ────────────────")
    IO.puts("")

    # math.sqrt
    fetch_and_display_doc("math", "sqrt")

    # json.dumps
    fetch_and_display_doc("json", "dumps")

    # os.path.join
    fetch_and_display_doc("os.path", "join")

    # re.match
    fetch_and_display_doc("re", "match")

    IO.puts("")
  end

  # ============================================================================
  # SECTION 2: Different Docstring Styles
  # ============================================================================

  defp demo_docstring_styles do
    IO.puts("─── SECTION 2: Docstring Style Detection ───────────────────")
    IO.puts("")

    # Google style example
    google_docstring = """
    Calculate the weighted average of values.

    This function computes a weighted average using the provided
    weights. If no weights are provided, all values are treated equally.

    Args:
        values (list[float]): The numeric values to average.
        weights (list[float], optional): Weights for each value.
            Defaults to equal weights.

    Returns:
        float: The weighted average of the input values.

    Raises:
        ValueError: If values is empty.
        TypeError: If values contains non-numeric types.

    Example:
        >>> weighted_avg([1, 2, 3], [0.5, 0.3, 0.2])
        1.7
    """

    display_style_demo("Google Style", google_docstring)

    # NumPy style example
    numpy_docstring = """
    Compute the discrete Fourier Transform.

    This function computes the one-dimensional n-point discrete
    Fourier Transform (DFT) with the efficient Fast Fourier
    Transform (FFT) algorithm.

    Parameters
    ----------
    a : array_like
        Input array, can be complex.
    n : int, optional
        Length of the transformed axis of the output.
        If n is smaller than the length of the input, the input is cropped.
    axis : int, optional
        Axis over which to compute the FFT. Default is -1.

    Returns
    -------
    complex ndarray
        The truncated or zero-padded input, transformed along the axis.

    Raises
    ------
    IndexError
        If axis is not a valid axis of a.

    Notes
    -----
    The formula for the DFT is :math:`A_k = \\sum_{m=0}^{n-1} a_m e^{-2\\pi i m k / n}`.

    Examples
    --------
    >>> import numpy as np
    >>> np.fft.fft([1, 2, 3, 4])
    array([10.+0.j, -2.+2.j, -2.+0.j, -2.-2.j])
    """

    display_style_demo("NumPy Style", numpy_docstring)

    # Sphinx style example
    sphinx_docstring = """
    Connect to a database and return a connection object.

    This function establishes a connection to the specified database
    using the provided credentials.

    :param host: The database server hostname.
    :type host: str
    :param port: The port number to connect on.
    :type port: int
    :param username: Database username for authentication.
    :type username: str
    :param password: Database password for authentication.
    :type password: str
    :param timeout: Connection timeout in seconds.
    :type timeout: float
    :returns: A database connection object.
    :rtype: Connection
    :raises ConnectionError: If the connection cannot be established.
    :raises AuthenticationError: If the credentials are invalid.
    """

    display_style_demo("Sphinx Style", sphinx_docstring)

    IO.puts("")
  end

  # ============================================================================
  # SECTION 3: Math Expression Rendering
  # ============================================================================

  defp demo_math_rendering do
    IO.puts("─── SECTION 3: Math Expression Rendering ───────────────────")
    IO.puts("")

    math_examples = [
      {
        "Inline math",
        "The quadratic formula is :math:`x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}`."
      },
      {
        "Multiple inline expressions",
        "Given :math:`f(x) = x^2` and :math:`g(x) = 2x`, then :math:`(f \\circ g)(x) = 4x^2`."
      },
      {
        "Greek letters",
        "The circumference is :math:`C = 2\\pi r` and area is :math:`A = \\pi r^2`."
      },
      {
        "Summation and integrals",
        "The sum :math:`\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}` and integral :math:`\\int_0^1 x^2 dx = \\frac{1}{3}`."
      },
      {
        "Matrix notation",
        "A matrix :math:`\\mathbf{A} = \\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}` has determinant :math:`|A| = ad - bc`."
      }
    ]

    for {name, text} <- math_examples do
      IO.puts("┌─ #{name}")
      IO.puts("│")
      IO.puts("│  ─── ORIGINAL (RST) ───")
      IO.puts("│  #{text}")
      IO.puts("│")
      rendered = MathRenderer.render(text)
      IO.puts("│  ─── RENDERED (Markdown) ───")
      IO.puts("│  #{rendered}")
      IO.puts("│")
      extracted = MathRenderer.extract_math(text)
      IO.puts("│  ─── EXTRACTED EXPRESSIONS ───")

      for expr <- extracted do
        IO.puts("│  - #{expr}")
      end

      IO.puts("│")
      IO.puts("└─ Math rendering complete")
      IO.puts("")
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp fetch_and_display_doc(module, function) do
    IO.puts("┌─ Fetching documentation for: #{module}.#{function}")
    IO.puts("│")
    IO.puts("│  Python function: #{module}.#{function}")
    IO.puts("│")

    # Fetch the raw docstring from Python
    case fetch_python_doc(module, function) do
      {:ok, raw_doc} when is_binary(raw_doc) and raw_doc != "" ->
        IO.puts("│  ─── RAW PYTHON DOCSTRING ───")
        display_indented(raw_doc, "│  ")
        IO.puts("│")

        # Parse the docstring
        parsed = RstParser.parse(raw_doc)
        IO.puts("│  ─── PARSED STRUCTURE ───")
        IO.puts("│  %{")
        IO.puts("│    short_description: #{inspect(parsed.short_description)},")
        IO.puts("│    params: #{format_params_summary(parsed.params)},")
        IO.puts("│    returns: #{inspect(parsed.returns)},")
        IO.puts("│    style: #{inspect(parsed.style)}")
        IO.puts("│  }")
        IO.puts("│")

        # Convert to Elixir markdown
        markdown = MarkdownConverter.convert(parsed)
        IO.puts("│  ─── RENDERED ELIXIR MARKDOWN ───")
        display_indented(markdown, "│  ")
        IO.puts("│")
        IO.puts("└─ Documentation extracted successfully")

      {:ok, nil} ->
        IO.puts("│  (No documentation available)")
        IO.puts("└─ No docstring found")

      {:ok, ""} ->
        IO.puts("│  (Empty documentation)")
        IO.puts("└─ Empty docstring")

      {:error, reason} ->
        IO.puts("│  Error: #{inspect(reason)}")
        IO.puts("└─ Failed to fetch documentation")
    end

    IO.puts("")
  end

  defp fetch_python_doc(module, function) do
    # Use snakepit_call to invoke inspect.getdoc on the Python function
    # First, we need to get the function object, then get its docstring
    case snakepit_call("importlib", "import_module", [module]) do
      {:ok, mod_obj} ->
        # Get the function from the module using builtins.getattr
        case snakepit_call("builtins", "getattr", [mod_obj, function, nil]) do
          {:ok, nil} ->
            {:ok, nil}

          {:ok, func_obj} ->
            # Get the docstring using inspect.getdoc
            snakepit_call("inspect", "getdoc", [func_obj])

          error ->
            error
        end

      error ->
        error
    end
  end

  defp display_style_demo(style_name, docstring) do
    IO.puts("┌─ #{style_name} Docstring")
    IO.puts("│")

    # Detect the style
    detected = RstParser.detect_style(docstring)
    IO.puts("│  Detected style: #{inspect(detected)}")
    IO.puts("│")

    IO.puts("│  ─── RAW DOCSTRING ───")
    display_indented(docstring, "│  ")
    IO.puts("│")

    # Parse
    parsed = RstParser.parse(docstring)
    IO.puts("│  ─── PARSED STRUCTURE ───")
    IO.puts("│  Short description: #{inspect(parsed.short_description)}")
    IO.puts("│  Long description: #{truncate(parsed.long_description, 60)}")
    IO.puts("│")
    IO.puts("│  Parameters (#{length(parsed.params)}):")

    for param <- parsed.params do
      optional_str = if param.optional, do: ", optional", else: ""
      type_str = if param.type_name, do: " : #{param.type_name}", else: ""
      IO.puts("│    - #{param.name}#{type_str}#{optional_str}")
    end

    IO.puts("│")
    IO.puts("│  Returns: #{format_returns(parsed.returns)}")
    IO.puts("│  Raises: #{format_raises(parsed.raises)}")
    IO.puts("│")

    # Convert to markdown
    markdown = MarkdownConverter.convert(parsed)
    IO.puts("│  ─── RENDERED ELIXIR MARKDOWN ───")
    display_indented(markdown, "│  ")
    IO.puts("│")
    IO.puts("└─ Style demo complete")
    IO.puts("")
  end

  defp display_indented(text, prefix) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.each(fn line ->
      IO.puts("#{prefix}#{line}")
    end)
  end

  defp display_indented(nil, prefix) do
    IO.puts("#{prefix}(nil)")
  end

  defp format_params_summary([]), do: "[]"

  defp format_params_summary(params) do
    names = Enum.map(params, fn p -> p.name end)
    "[#{Enum.join(names, ", ")}]"
  end

  defp format_returns(nil), do: "(none)"

  defp format_returns(%{type_name: type, description: desc}) do
    type_str = type || "unspecified"
    desc_str = if desc, do: " - #{truncate(desc, 40)}", else: ""
    "#{type_str}#{desc_str}"
  end

  defp format_raises([]), do: "(none)"

  defp format_raises(raises) do
    types = Enum.map(raises, fn r -> r.type_name end)
    Enum.join(types, ", ")
  end

  defp truncate(nil, _max), do: "(nil)"

  defp truncate(text, max) when is_binary(text) do
    if String.length(text) > max do
      String.slice(text, 0, max) <> "..."
    else
      text
    end
  end

  # Helper to call Python via Snakepit with proper payload format
  defp snakepit_call(python_module, python_function, args) do
    payload = %{
      "library" => python_module |> String.split(".") |> List.first(),
      "python_module" => python_module,
      "function" => python_function,
      "args" => args,
      "kwargs" => %{},
      "idempotent" => false
    }

    case Snakepit.execute("snakebridge.call", payload) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
      other -> {:ok, other}
    end
  end
end
