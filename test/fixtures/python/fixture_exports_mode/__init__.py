"""
Fixture package for SnakeBridge `module_mode: :exports`.

The root module explicitly exports a single public submodule (`api_mod`) and a
single class (`ApiClass`). Other modules exist on disk but are not exported and
should not be selected in exports mode.
"""

from . import api_mod

__all__ = ["api_mod", "ApiClass"]

ApiClass = api_mod.ApiClass

