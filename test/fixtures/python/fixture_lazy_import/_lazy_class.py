"""Lazy-loaded class module."""


class LazyClass:
    """A class that is lazily loaded via __getattr__.

    This class should be discovered by introspection even though
    it's not directly in the parent module's namespace until accessed.
    """

    def __init__(self, name: str, value: int = 0):
        """Initialize LazyClass.

        Args:
            name: The name of the instance.
            value: An optional integer value.
        """
        self.name = name
        self.value = value

    def process(self, data: str) -> str:
        """Process some data.

        Args:
            data: Input data to process.

        Returns:
            Processed data string.
        """
        return f"{self.name}: {data}"

    def get_value(self) -> int:
        """Get the current value."""
        return self.value
