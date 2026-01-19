from typing import overload


@overload
def parse(value: int) -> int: ...


@overload
def parse(value: str) -> str: ...


def parse(value): ...
