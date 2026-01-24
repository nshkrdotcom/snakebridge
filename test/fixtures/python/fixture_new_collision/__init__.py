"""
Test fixture for method name collision with constructor.

This fixture tests the case where a Python class has both __init__
and a method named 'new', which would conflict with SnakeBridge's
generated constructor (which is also named 'new').
"""


class ClassWithNewMethod:
    """A class that has both __init__ and a method named 'new'."""

    def __init__(self, value: int):
        """Initialize with a value.

        Args:
            value: The initial value.
        """
        self.value = value

    def new(self, other_value: int) -> "ClassWithNewMethod":
        """Create a new instance with a different value.

        This is a factory method that conflicts with the constructor name.

        Args:
            other_value: Value for the new instance.

        Returns:
            A new ClassWithNewMethod instance.
        """
        return ClassWithNewMethod(other_value)

    def get_value(self) -> int:
        """Get the current value."""
        return self.value


class ClassWithoutNewMethod:
    """A normal class without the collision issue."""

    def __init__(self, name: str):
        """Initialize with a name."""
        self.name = name

    def greet(self) -> str:
        """Return a greeting."""
        return f"Hello, {self.name}"
