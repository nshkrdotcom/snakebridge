"""Tests for SnakeBridge gRPC streaming client behavior."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import snakepit_bridge_pb2 as pb2
from google.protobuf import any_pb2

from snakebridge_client import BridgeClient


class _FakeStream:
    def __init__(self, chunks):
        self._it = iter(chunks)
        self.cancelled = False

    def __iter__(self):
        return self

    def __next__(self):
        return next(self._it)

    def cancel(self):
        self.cancelled = True


class _FakeStub:
    def __init__(self):
        self.streaming_calls = []
        self.execute_calls = []

    def ExecuteStreamingTool(self, request, metadata=None, timeout=None):
        self.streaming_calls.append((request, metadata, timeout))
        return _FakeStream(
            [
                pb2.ToolChunk(
                    chunk_id="c1",
                    data=b'{"step":1,"total":2}',
                    is_final=False,
                    metadata={"k": "v"},
                ),
                pb2.ToolChunk(
                    chunk_id="c2",
                    data=b'{"status":"done"}',
                    is_final=True,
                    metadata={"execution_time_ms": "5"},
                ),
            ]
        )

    def ExecuteTool(self, *args, **kwargs):
        self.execute_calls.append((args, kwargs))
        raise AssertionError("ExecuteTool should not be used for streaming")


class _UnaryStub:
    def __init__(self):
        self.execute_calls = []

    def ExecuteTool(self, request, metadata=None, timeout=None):
        self.execute_calls.append((request, metadata, timeout))
        return pb2.ExecuteToolResponse(
            success=True,
            result=any_pb2.Any(
                type_url="type.googleapis.com/google.protobuf.StringValue",
                value=b'"ok"',
            ),
        )


def test_execute_tool_sets_request_metadata_and_correlation_header():
    stub = _UnaryStub()
    client = BridgeClient(stub=stub)

    result = client.execute_tool(
        "session-1",
        "tool",
        {"answer": 42},
        request_metadata={"thread_sensitive": True, "extra": "1"},
        correlation_id="cid-123",
    )

    assert result == "ok"
    assert len(stub.execute_calls) == 1

    request, call_md, _timeout = stub.execute_calls[0]
    assert request.session_id == "session-1"
    assert request.tool_name == "tool"
    assert request.parameters["answer"].value == b"42"
    assert request.metadata["correlation_id"] == "cid-123"
    assert request.metadata["thread_sensitive"] == "True"
    assert request.metadata["extra"] == "1"

    assert any(
        k == "x-snakepit-correlation-id" and v == "cid-123" for (k, v) in (call_md or [])
    )


def test_execute_tool_rejects_non_bytes_binary_parameters():
    stub = _UnaryStub()
    client = BridgeClient(stub=stub)

    try:
        client.execute_tool(
            "s",
            "t",
            binary_parameters={"bad": "not-bytes"},
            correlation_id="cid",
        )
    except TypeError as exc:
        assert "binary_parameters" in str(exc)
    else:
        raise AssertionError("Expected TypeError for non-bytes binary_parameters")


def test_execute_streaming_tool_uses_streaming_rpc_and_sets_correlation_header():
    stub = _FakeStub()
    client = BridgeClient(stub=stub)

    out = list(
        client.execute_streaming_tool(
            "session-1",
            "stream_tool",
            {"steps": 2},
            binary_parameters={"blob": b"\x00\x01"},
            correlation_id="cid-123",
        )
    )

    assert len(stub.streaming_calls) == 1
    assert stub.execute_calls == []
    request, call_md, _timeout = stub.streaming_calls[0]

    # Ensures we used ExecuteStreamingTool and encoded parameters in Any.value as raw JSON.
    assert request.session_id == "session-1"
    assert request.tool_name == "stream_tool"
    assert "steps" in request.parameters
    assert request.parameters["steps"].type_url == "type.googleapis.com/google.protobuf.StringValue"
    assert request.parameters["steps"].value == b"2"
    assert request.binary_parameters["blob"] == b"\x00\x01"

    # Correlation header is present on RPC metadata.
    assert any(k == "x-snakepit-correlation-id" and v == "cid-123" for (k, v) in (call_md or []))

    # Chunk decoding behavior.
    assert out[0]["step"] == 1
    assert out[0]["total"] == 2
    assert out[0]["is_final"] is False
    assert out[0]["_metadata"]["k"] == "v"
    assert out[0]["_chunk_id"] == "c1"

    assert out[-1]["status"] == "done"
    assert out[-1]["is_final"] is True
    assert out[-1]["_metadata"]["execution_time_ms"] == "5"
    assert out[-1]["_chunk_id"] == "c2"


def test_execute_streaming_tool_with_empty_and_non_json_chunks():
    """Test handling of chunks with empty or non-JSON data."""

    class EmptyChunkStub:
        def __init__(self):
            self.calls = []

        def ExecuteStreamingTool(self, request, metadata=None, timeout=None):
            self.calls.append((request, metadata, timeout))
            return _FakeStream(
                [
                    pb2.ToolChunk(chunk_id="e1", data=b"", is_final=False),
                    pb2.ToolChunk(chunk_id="e2", data=b"not json", is_final=True),
                ]
            )

    stub = EmptyChunkStub()
    client = BridgeClient(stub=stub)

    out = list(client.execute_streaming_tool("s", "t", correlation_id="cid"))

    # Empty data returns empty dict + is_final
    assert out[0] == {"is_final": False, "_chunk_id": "e1"}

    # Non-JSON data is preserved as bytes in "data" key
    assert out[1]["data"] == b"not json"
    assert out[1]["is_final"] is True
    assert out[1]["_chunk_id"] == "e2"


def test_execute_streaming_tool_auto_generates_correlation_id():
    """Test that correlation ID is auto-generated if not provided."""
    stub = _FakeStub()
    client = BridgeClient(stub=stub)

    # Don't pass correlation_id
    list(client.execute_streaming_tool("s", "t"))

    assert len(stub.streaming_calls) == 1
    _request, call_md, _timeout = stub.streaming_calls[0]

    # Should have generated a correlation ID
    corr_headers = [v for (k, v) in (call_md or []) if k == "x-snakepit-correlation-id"]
    assert len(corr_headers) == 1
    assert corr_headers[0]


def test_execute_streaming_tool_stops_on_final_chunk():
    class ExtraChunkStub:
        def __init__(self):
            self.calls = []

        def ExecuteStreamingTool(self, request, metadata=None, timeout=None):
            self.calls.append((request, metadata, timeout))
            return _FakeStream(
                [
                    pb2.ToolChunk(chunk_id="c1", data=b'{"progress":1}', is_final=False),
                    pb2.ToolChunk(chunk_id="c2", data=b'{"progress":2}', is_final=True),
                    pb2.ToolChunk(chunk_id="c3", data=b'{"progress":3}', is_final=False),
                ]
            )

    stub = ExtraChunkStub()
    client = BridgeClient(stub=stub)

    out = list(client.execute_streaming_tool("s", "t", correlation_id="cid"))

    assert [chunk.get("progress") for chunk in out] == [1, 2]


def test_execute_streaming_tool_rejects_non_bytes_binary_parameters():
    stub = _FakeStub()
    client = BridgeClient(stub=stub)

    try:
        list(
            client.execute_streaming_tool(
                "s",
                "t",
                binary_parameters={"bad": "not-bytes"},
                correlation_id="cid",
            )
        )
    except TypeError as exc:
        assert "binary_parameters" in str(exc)
    else:
        raise AssertionError("Expected TypeError for non-bytes binary_parameters")
