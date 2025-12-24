"""
SnakeBridge Python Adapter for Snakepit.

Provides dynamic Python library integration via:
- describe_library: Introspect any Python module
- call_python: Execute any Python code dynamically
- call_python_stream: Execute Python code dynamically with streaming results
"""

from .adapter import SnakeBridgeAdapter

__all__ = ["SnakeBridgeAdapter"]
__version__ = "0.1.0"
