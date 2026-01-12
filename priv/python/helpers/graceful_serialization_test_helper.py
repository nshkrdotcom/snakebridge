"""
Test helpers for graceful serialization integration tests.

These helpers return data structures that test the graceful serialization
behavior - containers with non-serializable objects that should result in
nested refs rather than ref-wrapped containers.

Uses REAL Python stdlib objects (re.Pattern) - no mocks.
"""

import re


def get_validation_configs():
    """
    Return a list of validation configurations with compiled regex patterns.

    This is a real-world pattern: storing compiled patterns alongside metadata
    for form validation, input parsing, API request validation, etc.

    Expected behavior: The outer list and inner dicts should be preserved,
    with only the 'pattern' field becoming a ref (re.Pattern is non-serializable).
    """
    return [
        {
            "name": "email",
            "pattern": re.compile(r"^[\w\.-]+@[\w\.-]+\.\w+$"),
            "error_message": "Invalid email format",
            "required": True,
        },
        {
            "name": "phone",
            "pattern": re.compile(r"^\d{3}-\d{3}-\d{4}$"),
            "error_message": "Phone must be XXX-XXX-XXXX",
            "required": False,
        },
        {
            "name": "zip_code",
            "pattern": re.compile(r"^\d{5}(-\d{4})?$"),
            "error_message": "Invalid ZIP code",
            "required": True,
        },
    ]


def get_list_with_pattern():
    """Return a list containing a compiled regex pattern."""
    return [1, re.compile(r"\d+"), 3]


def get_dict_with_pattern():
    """Return a dict containing a compiled regex pattern."""
    return {"a": 1, "b": re.compile(r"[a-z]+"), "c": "hello"}


def get_nested_structure():
    """Return a deeply nested structure with a compiled pattern."""
    return {
        "level1": {
            "level2": {
                "level3": [1, 2, re.compile(r"^\w+$"), 4]
            }
        }
    }


def get_multiple_patterns():
    """Return a list with multiple compiled patterns at different positions."""
    return [
        re.compile(r"^start"),
        "separator",
        re.compile(r"middle"),
        100,
        re.compile(r"end$"),
    ]


def get_tuple_with_pattern():
    """Return a tuple containing a compiled pattern."""
    return (1, re.compile(r"[A-Z]{2,4}"), 3)


def get_dict_with_generator():
    """Return a dict containing a generator and a regular value."""
    return {"stream": (x * 2 for x in range(5)), "status": "ok"}


def get_pattern_with_flags():
    """Return a pattern compiled with flags to show flag preservation."""
    return {
        "pattern": re.compile(r"hello\s+world", re.IGNORECASE | re.MULTILINE),
        "description": "Case-insensitive multiline pattern",
        "test_string": "HELLO   WORLD",
    }


# Helper registry for SnakeBridge helper pack
__snakebridge_helpers__ = {
    "graceful_serialization.validation_configs": get_validation_configs,
    "graceful_serialization.list_with_pattern": get_list_with_pattern,
    "graceful_serialization.dict_with_pattern": get_dict_with_pattern,
    "graceful_serialization.nested_structure": get_nested_structure,
    "graceful_serialization.multiple_patterns": get_multiple_patterns,
    "graceful_serialization.tuple_with_pattern": get_tuple_with_pattern,
    "graceful_serialization.dict_with_generator": get_dict_with_generator,
    "graceful_serialization.pattern_with_flags": get_pattern_with_flags,
}
