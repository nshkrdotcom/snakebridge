"""
SnakeBridge Snakepit Adapter

Provides the Snakepit adapter interface for SnakeBridge.
This module is called by the Snakepit runtime to execute Python functions
and return results to Elixir.

Main function:
    snakebridge_call(module: str, function: str, args: dict) -> dict

The adapter:
1. Imports the specified Python module
2. Gets the specified function from the module
3. Decodes the arguments from SnakeBridge format
4. Calls the function with the decoded arguments
5. Encodes the result back to SnakeBridge format
6. Returns a success/error response
"""

import sys
import importlib
import inspect
import traceback
from typing import Any, Dict

# Import the SnakeBridge type encoding system
try:
    from snakebridge_types import decode, encode, encode_result, encode_error
except ImportError:
    # If running as a script, try relative import
    import os
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from snakebridge_types import decode, encode, encode_result, encode_error


# Module cache to avoid repeated imports
_module_cache: Dict[str, Any] = {}


def snakebridge_call(module: str, function: str, args: dict) -> dict:
    """
    Call a Python function from SnakeBridge.

    This is the main entry point called by the Snakepit adapter.

    Args:
        module: The Python module name (e.g., 'math', 'numpy')
        function: The function name to call (e.g., 'sqrt', 'array')
        args: Dictionary of argument names to values (in SnakeBridge encoded format)

    Returns:
        Dictionary with either:
            - {"success": True, "result": <encoded_result>}
            - {"success": False, "error": <error_message>, "error_type": <error_type>}

    Examples:
        >>> snakebridge_call('math', 'sqrt', {'x': 16})
        {'success': True, 'result': 4.0}

        >>> snakebridge_call('math', 'gcd', {'a': 48, 'b': 18})
        {'success': True, 'result': 6}

        >>> snakebridge_call('statistics', 'mean', {'data': [1, 2, 3, 4, 5]})
        {'success': True, 'result': 3.0}
    """
    try:
        # Import the module (use cache if available)
        if module in _module_cache:
            mod = _module_cache[module]
        else:
            try:
                mod = importlib.import_module(module)
                _module_cache[module] = mod
            except ImportError as e:
                return encode_error(ImportError(f"Failed to import module '{module}': {str(e)}"))

        # Get the function from the module
        if not hasattr(mod, function):
            return encode_error(AttributeError(f"Module '{module}' has no function '{function}'"))

        func = getattr(mod, function)

        # Check if it's callable
        if not callable(func):
            return encode_error(TypeError(f"'{module}.{function}' is not callable"))

        # Decode arguments from SnakeBridge format
        try:
            decoded_args = {name: decode(value) for name, value in args.items()}
        except Exception as e:
            return encode_error(ValueError(f"Failed to decode arguments: {str(e)}"))

        # Call the function
        # Try to determine if we should use positional or keyword arguments
        try:
            # First, try with keyword arguments (most flexible)
            try:
                result = func(**decoded_args)
            except TypeError as e:
                error_msg = str(e)
                # If it fails because it doesn't accept keyword arguments,
                # try with positional arguments instead
                if "keyword argument" in error_msg.lower():
                    # Try to get the signature to determine argument order
                    try:
                        sig = inspect.signature(func)
                        # Create positional args in parameter order
                        positional_args = []
                        for param_name in sig.parameters.keys():
                            if param_name in decoded_args:
                                positional_args.append(decoded_args[param_name])

                        # If we didn't find any matching parameters, it might be a *args function
                        # Fall back to using values in insertion order
                        if not positional_args:
                            positional_args = list(decoded_args.values())

                        result = func(*positional_args)
                    except (ValueError, TypeError):
                        # Can't get signature, use values in insertion order (Python 3.7+ dicts)
                        positional_args = list(decoded_args.values())
                        result = func(*positional_args)
                else:
                    # Re-raise if it's a different kind of TypeError
                    raise
        except TypeError as e:
            # Provide helpful error message for argument mismatches
            error_msg = str(e)
            return encode_error(TypeError(f"Argument error calling {module}.{function}: {error_msg}"))
        except Exception as e:
            # Return any exception from the function call
            return encode_error(e)

        # Encode and return the result
        return encode_result(result)

    except Exception as e:
        # Catch any unexpected errors
        error_info = {
            "success": False,
            "error": str(e),
            "error_type": type(e).__name__,
            "traceback": traceback.format_exc()
        }
        return error_info


def snakebridge_batch_call(calls: list) -> list:
    """
    Execute multiple function calls in a batch.

    Args:
        calls: List of call specifications, each with 'module', 'function', and 'args'

    Returns:
        List of results corresponding to each call

    Example:
        >>> snakebridge_batch_call([
        ...     {'module': 'math', 'function': 'sqrt', 'args': {'x': 16}},
        ...     {'module': 'math', 'function': 'gcd', 'args': {'a': 48, 'b': 18}}
        ... ])
        [{'success': True, 'result': 4.0}, {'success': True, 'result': 6}]
    """
    results = []
    for call in calls:
        try:
            module = call['module']
            function = call['function']
            args = call.get('args', {})
            result = snakebridge_call(module, function, args)
            results.append(result)
        except Exception as e:
            results.append(encode_error(e))
    return results


def snakebridge_get_attribute(module: str, attribute: str) -> dict:
    """
    Get an attribute or constant from a module.

    Args:
        module: The Python module name
        attribute: The attribute name to get

    Returns:
        Dictionary with either:
            - {"success": True, "result": <encoded_value>}
            - {"success": False, "error": <error_message>}

    Example:
        >>> snakebridge_get_attribute('math', 'pi')
        {'success': True, 'result': 3.141592653589793}
    """
    try:
        # Import the module
        if module in _module_cache:
            mod = _module_cache[module]
        else:
            try:
                mod = importlib.import_module(module)
                _module_cache[module] = mod
            except ImportError as e:
                return encode_error(ImportError(f"Failed to import module '{module}': {str(e)}"))

        # Get the attribute
        if not hasattr(mod, attribute):
            return encode_error(AttributeError(f"Module '{module}' has no attribute '{attribute}'"))

        value = getattr(mod, attribute)

        # Encode and return the value
        return encode_result(value)

    except Exception as e:
        return encode_error(e)


def snakebridge_create_instance(module: str, class_name: str, args: dict) -> dict:
    """
    Create an instance of a class.

    Args:
        module: The Python module name
        class_name: The class name to instantiate
        args: Dictionary of constructor arguments

    Returns:
        Dictionary with either success or error

    Note:
        Instance objects cannot be serialized, so this is mainly useful
        for testing or when combined with a session/state system.
    """
    try:
        # Import the module
        if module in _module_cache:
            mod = _module_cache[module]
        else:
            try:
                mod = importlib.import_module(module)
                _module_cache[module] = mod
            except ImportError as e:
                return encode_error(ImportError(f"Failed to import module '{module}': {str(e)}"))

        # Get the class
        if not hasattr(mod, class_name):
            return encode_error(AttributeError(f"Module '{module}' has no class '{class_name}'"))

        cls = getattr(mod, class_name)

        # Check if it's a class
        if not isinstance(cls, type):
            return encode_error(TypeError(f"'{module}.{class_name}' is not a class"))

        # Decode arguments
        decoded_args = {name: decode(value) for name, value in args.items()}

        # Create instance
        instance = cls(**decoded_args)

        # Encode and return (note: complex objects may not serialize well)
        return encode_result(instance)

    except Exception as e:
        return encode_error(e)


# Make the module callable for testing
if __name__ == "__main__":
    import json

    # Simple test runner
    if len(sys.argv) > 1:
        # Test with command-line arguments
        # Usage: python snakebridge_adapter.py <module> <function> <json_args>
        if len(sys.argv) >= 4:
            module = sys.argv[1]
            function = sys.argv[2]
            args_json = sys.argv[3]
            args = json.loads(args_json)

            result = snakebridge_call(module, function, args)
            print(json.dumps(result, indent=2))
        else:
            print("Usage: python snakebridge_adapter.py <module> <function> <json_args>")
    else:
        # Run built-in tests
        print("Running SnakeBridge adapter tests...\n")

        # Test 1: math.sqrt
        print("Test 1: math.sqrt(16)")
        result = snakebridge_call('math', 'sqrt', {'x': 16})
        print(json.dumps(result, indent=2))
        assert result['success'] == True
        assert result['result'] == 4.0
        print("PASS\n")

        # Test 2: math.gcd
        print("Test 2: math.gcd(48, 18)")
        result = snakebridge_call('math', 'gcd', {'a': 48, 'b': 18})
        print(json.dumps(result, indent=2))
        assert result['success'] == True
        assert result['result'] == 6
        print("PASS\n")

        # Test 3: Error handling - module not found
        print("Test 3: Error handling - nonexistent module")
        result = snakebridge_call('nonexistent_module', 'func', {})
        print(json.dumps(result, indent=2))
        assert result['success'] == False
        print("PASS\n")

        # Test 4: Error handling - function not found
        print("Test 4: Error handling - nonexistent function")
        result = snakebridge_call('math', 'nonexistent_function', {})
        print(json.dumps(result, indent=2))
        assert result['success'] == False
        print("PASS\n")

        # Test 5: Complex types - tuple encoding
        print("Test 5: Complex types - math.gcd with large numbers")
        result = snakebridge_call('math', 'gcd', {'a': 1071, 'b': 462})
        print(json.dumps(result, indent=2))
        assert result['success'] == True
        assert result['result'] == 21
        print("PASS\n")

        # Test 6: Get attribute
        print("Test 6: Get math.pi")
        result = snakebridge_get_attribute('math', 'pi')
        print(json.dumps(result, indent=2))
        assert result['success'] == True
        assert abs(result['result'] - 3.141592653589793) < 0.0001
        print("PASS\n")

        print("All tests passed!")
