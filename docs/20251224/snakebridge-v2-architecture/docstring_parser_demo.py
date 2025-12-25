#!/usr/bin/env python3
"""
Demonstration of Python Docstring Parsing for Snakebridge v2

This script demonstrates the capabilities of docstring_parser library
for extracting and transforming Python documentation.

To run this demo:
    pip install docstring-parser
    python3 docstring_parser_demo.py
"""

# Example module with various docstring styles for testing

def google_style_example(name, age, city="Unknown"):
    """Demonstrate Google-style docstring.

    This function shows a complete Google-style docstring with
    all common sections.

    Args:
        name (str): Person's full name.
        age (int): Person's age in years.
        city (str, optional): City of residence. Defaults to "Unknown".

    Returns:
        dict: Dictionary containing person information with keys:
            - name: str
            - age: int
            - city: str

    Raises:
        ValueError: If age is negative.
        TypeError: If name is not a string.

    Example:
        >>> google_style_example("Alice", 30, "NYC")
        {'name': 'Alice', 'age': 30, 'city': 'NYC'}

    Note:
        This is just a demonstration function.
    """
    if age < 0:
        raise ValueError("Age cannot be negative")
    return {"name": name, "age": age, "city": city}


def numpy_style_example(data, window_size, overlap=0.5):
    """Demonstrate NumPy-style docstring.

    Process data using a sliding window approach with configurable
    overlap between consecutive windows.

    Parameters
    ----------
    data : array_like
        Input data array to process.
    window_size : int
        Size of the processing window in samples.
    overlap : float, optional
        Overlap fraction between windows, must be in [0, 1).
        Default is 0.5 (50% overlap).

    Returns
    -------
    result : ndarray
        Processed data with shape (n_windows, window_size).
    metadata : dict
        Processing metadata containing:
        - n_windows: int, number of windows
        - step_size: int, samples between window starts

    Raises
    ------
    ValueError
        If window_size > len(data) or overlap not in [0, 1).

    See Also
    --------
    scipy.signal.spectrogram : Related signal processing function.

    Notes
    -----
    The window overlap is computed as:

    .. math:: step = window\_size * (1 - overlap)

    Examples
    --------
    Process a simple array with 3-sample window:

    >>> import numpy as np
    >>> data = np.arange(10)
    >>> result, metadata = numpy_style_example(data, 3, overlap=0)
    >>> print(result.shape)
    (8, 3)

    References
    ----------
    .. [1] Smith, J. "Windowed Signal Processing", Journal, 2020.
    """
    pass


def sphinx_style_example(x, y, mode='add'):
    """Demonstrate Sphinx/reStructuredText style docstring.

    Perform a mathematical operation on two numbers based on
    the specified mode.

    :param x: First operand
    :type x: float
    :param y: Second operand
    :type y: float
    :param mode: Operation mode ('add', 'subtract', 'multiply', 'divide')
    :type mode: str
    :returns: Result of the operation
    :rtype: float
    :raises ValueError: If mode is not recognized
    :raises ZeroDivisionError: If mode is 'divide' and y is zero

    .. note::
        Division uses floating-point arithmetic.

    .. warning::
        No overflow checking is performed.

    Example usage::

        >>> sphinx_style_example(10, 5, mode='add')
        15.0

        >>> sphinx_style_example(10, 5, mode='divide')
        2.0

    .. seealso::
        :func:`math.fsum` for higher precision addition
    """
    pass


class ExampleClass:
    """Example class with various methods.

    This class demonstrates docstrings in a class context with
    instance variables, methods, and properties.

    Attributes:
        name (str): Instance name.
        value (int): Numeric value associated with instance.
        _private (bool): Private internal flag.
    """

    def __init__(self, name, value):
        """Initialize the example instance.

        Args:
            name (str): Name for this instance.
            value (int): Initial value.

        Raises:
            TypeError: If name is not a string.
        """
        self.name = name
        self.value = value
        self._private = False

    def increment(self, amount=1):
        """Increment the internal value.

        Parameters
        ----------
        amount : int, optional
            Amount to add to current value (default is 1).

        Returns
        -------
        int
            New value after incrementing.

        Examples
        --------
        >>> obj = ExampleClass("test", 10)
        >>> obj.increment(5)
        15
        >>> obj.value
        15
        """
        self.value += amount
        return self.value


# Parsing demonstration
if __name__ == "__main__":
    try:
        from docstring_parser import parse, DocstringStyle
    except ImportError:
        print("Error: docstring_parser not installed")
        print("Install with: pip install docstring-parser")
        exit(1)

    import inspect

    print("=" * 70)
    print("Python Docstring Parsing Demo for Snakebridge v2")
    print("=" * 70)

    # Parse Google style
    print("\n### GOOGLE STYLE ###\n")
    google_doc = inspect.getdoc(google_style_example)
    google_parsed = parse(google_doc, style=DocstringStyle.GOOGLE)

    print(f"Short: {google_parsed.short_description}")
    print(f"Params: {len(google_parsed.params)}")
    for p in google_parsed.params:
        optional = " (optional)" if p.is_optional else ""
        print(f"  - {p.arg_name}: {p.type_name}{optional} - {p.description[:40]}...")
    print(f"Returns: {google_parsed.returns.type_name} - {google_parsed.returns.description[:50]}...")
    print(f"Raises: {len(google_parsed.raises)} exceptions")

    # Parse NumPy style
    print("\n### NUMPY STYLE ###\n")
    numpy_doc = inspect.getdoc(numpy_style_example)
    numpy_parsed = parse(numpy_doc, style=DocstringStyle.NUMPYDOC)

    print(f"Short: {numpy_parsed.short_description}")
    print(f"Params: {len(numpy_parsed.params)}")
    for p in numpy_parsed.params:
        print(f"  - {p.arg_name}: {p.type_name}")
    print(f"Returns: {numpy_parsed.returns.type_name if numpy_parsed.returns else 'None'}")

    # Parse Sphinx style
    print("\n### SPHINX STYLE ###\n")
    sphinx_doc = inspect.getdoc(sphinx_style_example)
    sphinx_parsed = parse(sphinx_doc, style=DocstringStyle.REST)

    print(f"Short: {sphinx_parsed.short_description}")
    print(f"Params: {len(sphinx_parsed.params)}")
    for p in sphinx_parsed.params:
        print(f"  - {p.arg_name}: {p.type_name}")

    # Auto-detection demo
    print("\n### AUTO-DETECTION ###\n")

    test_docs = {
        "google": google_doc,
        "numpy": numpy_doc,
        "sphinx": sphinx_doc
    }

    for name, doc in test_docs.items():
        parsed = parse(doc, style=DocstringStyle.AUTO)
        print(f"{name.upper()}: Detected {len(parsed.params)} params, "
              f"returns={parsed.returns is not None}, "
              f"raises={len(parsed.raises)}")

    # Generate Elixir-style docs (demonstration)
    print("\n### ELIXIR DOC GENERATION DEMO ###\n")

    def generate_elixir_doc(parsed, func_name):
        """Simple Elixir doc generator."""
        lines = [f'@doc """', parsed.short_description or "", ""]

        if parsed.long_description:
            lines.extend([parsed.long_description, ""])

        if parsed.params:
            lines.append("## Parameters")
            lines.append("")
            for p in parsed.params:
                type_str = f" (type: `{p.type_name}`)" if p.type_name else ""
                lines.append(f"- `{p.arg_name}` - {p.description}{type_str}")
            lines.append("")

        if parsed.returns:
            lines.append("## Returns")
            lines.append("")
            lines.append(f"Returns `{parsed.returns.type_name or 'term()'}`. {parsed.returns.description or ''}")
            lines.append("")

        lines.append('"""')
        lines.append(f"def {func_name}(...) do")
        lines.append("  # Implementation")
        lines.append("end")

        return "\n".join(lines)

    elixir_doc = generate_elixir_doc(google_parsed, "google_style_example")
    print(elixir_doc)

    print("\n" + "=" * 70)
    print("Demo completed successfully!")
    print("=" * 70)
