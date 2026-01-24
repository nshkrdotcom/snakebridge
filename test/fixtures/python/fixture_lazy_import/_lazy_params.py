"""Lazy-loaded params module."""

from dataclasses import dataclass
from typing import Optional, List


@dataclass
class LazyParams:
    """Parameters class that is lazily loaded.

    Similar to vllm's SamplingParams which uses lazy loading.
    """

    temperature: float = 1.0
    max_tokens: int = 100
    stop: Optional[List[str]] = None

    def clone(self) -> "LazyParams":
        """Create a copy of the params."""
        return LazyParams(
            temperature=self.temperature,
            max_tokens=self.max_tokens,
            stop=self.stop.copy() if self.stop else None,
        )
