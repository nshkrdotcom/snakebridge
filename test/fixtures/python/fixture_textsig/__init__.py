"""Text signature fixture module."""


def text_sig_func(a, b, c=None):
    """Function with text signature only."""
    return (a, b, c)


# Force inspect.signature to fail by providing invalid __signature__.
text_sig_func.__signature__ = "invalid"
text_sig_func.__text_signature__ = "(a, b, /, c=None)"
