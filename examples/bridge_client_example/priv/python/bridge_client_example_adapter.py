"""
Minimal adapter for BridgeClient example.

Tools:
  - add: sum two numbers
  - stream_count: stream count-based chunks (includes a raw-bytes chunk)
"""

import time


class BridgeClientExampleAdapter:
    def execute_tool(self, tool_name: str, arguments: dict, context):
        arguments = arguments or {}

        if tool_name == "add":
            return float(arguments.get("a", 0)) + float(arguments.get("b", 0))

        if tool_name == "stream_count":
            count = int(arguments.get("count", 3))
            delay = float(arguments.get("delay", 0.0))

            def _iter():
                for idx in range(count):
                    if idx == count - 1:
                        yield b"done"
                    else:
                        yield {"value": idx + 1, "total": count}
                    if delay > 0:
                        time.sleep(delay)

            return _iter()

        raise AttributeError(f"Tool '{tool_name}' not supported by BridgeClientExampleAdapter")
