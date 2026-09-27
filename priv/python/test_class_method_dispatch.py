import sys
import types

from snakebridge_adapter import (
    MIN_SUPPORTED_VERSION,
    PROTOCOL_VERSION,
    SnakeBridgeAdapter,
    _module_cache,
)


MODULE_NAME = "snakebridge_test_descriptor_dispatch"


class DescriptorDemo:
    @classmethod
    def from_value(cls, value, scale=2):
        return {"class": cls.__name__, "value": value * scale}

    @staticmethod
    def add(left, right=1):
        return left + right


def _install_module():
    module = types.ModuleType(MODULE_NAME)
    module.DescriptorDemo = DescriptorDemo
    sys.modules[MODULE_NAME] = module
    _module_cache.pop(MODULE_NAME, None)


def _remove_module():
    _module_cache.pop(MODULE_NAME, None)
    sys.modules.pop(MODULE_NAME, None)


def _payload(function, args=None, kwargs=None):
    return {
        "protocol_version": PROTOCOL_VERSION,
        "min_supported_version": MIN_SUPPORTED_VERSION,
        "call_type": "class_method",
        "python_module": MODULE_NAME,
        "library": MODULE_NAME,
        "class": "DescriptorDemo",
        "function": function,
        "args": args or [],
        "kwargs": kwargs or {},
        "session_id": "descriptor-test",
    }


class TestClassMethodDispatch:
    def setup_method(self):
        _install_module()

    def teardown_method(self):
        _remove_module()

    def test_dispatches_classmethod_on_python_class(self):
        adapter = SnakeBridgeAdapter()

        result = adapter.execute_tool(
            "snakebridge.call",
            _payload("from_value", [4], {"scale": 3}),
            None,
        )

        assert result == {
            "class": "DescriptorDemo",
            "value": 12,
        }

    def test_dispatches_staticmethod_on_python_class(self):
        adapter = SnakeBridgeAdapter()

        result = adapter.execute_tool(
            "snakebridge.call",
            _payload("add", [4], {"right": 5}),
            None,
        )

        assert result == 9
