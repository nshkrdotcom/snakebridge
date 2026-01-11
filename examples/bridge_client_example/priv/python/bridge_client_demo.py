"""
BridgeClient demo script.

Uses ExecuteTool and ExecuteStreamingTool against the Elixir BridgeServer.
"""

import os
import sys

from snakebridge_client import BridgeClient


def main() -> int:
    address = os.environ.get("SNAKEPIT_GRPC_ADDRESS") or os.environ.get(
        "SNAKEPIT_GRPC_ADDR", "localhost:50051"
    )
    session_id = os.environ.get("SNAKEPIT_SESSION_ID")
    if not session_id:
        print("SNAKEPIT_SESSION_ID is required", file=sys.stderr)
        return 2

    client = BridgeClient(address)
    try:
        result = client.execute_tool(
            session_id,
            "add",
            {"a": 2, "b": 3},
            correlation_id="bridge-client-demo",
        )
        print(f"add result: {result}")

        for chunk in client.execute_streaming_tool(
            session_id,
            "stream_count",
            {"count": 3, "delay": 0.01},
            correlation_id="bridge-client-demo",
        ):
            print(f"chunk: {chunk}")
    finally:
        client.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
