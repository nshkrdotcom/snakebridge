"""
SnakeBridge gRPC client helpers.

This module provides a small client wrapper for calling Snakepit's BridgeService
from external Python processes.

Key behaviors:
  - Uses BridgeService.ExecuteStreamingTool for streaming (server-side streaming RPC)
  - Propagates correlation IDs via the gRPC header: "x-snakepit-correlation-id"
  - Decodes ToolChunk.data as UTF-8 JSON when possible; falls back to raw bytes

Interoperability note:
Snakepit's BridgeServer expects google.protobuf.Any.value to contain raw JSON bytes
when type_url is "type.googleapis.com/google.protobuf.StringValue" (custom convention).
This client encodes parameters accordingly.
"""

from __future__ import annotations

from contextvars import ContextVar
import json
import uuid
from typing import Any, Dict, Iterator, Mapping, Optional, Tuple

import grpc
from google.protobuf import any_pb2

import snakepit_bridge_pb2 as pb2
import snakepit_bridge_pb2_grpc as pb2_grpc

try:
    from snakepit_bridge import telemetry as _telemetry
except Exception:
    _telemetry = None


_STRING_ANY_TYPE_URL = "type.googleapis.com/google.protobuf.StringValue"
_CORRELATION_HEADER = "x-snakepit-correlation-id"
_fallback_correlation_id: ContextVar[Optional[str]] = ContextVar(
    "snakebridge_correlation_id", default=None
)


def _json_bytes(value: Any) -> bytes:
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def _encode_any_json(value: Any) -> any_pb2.Any:
    # Custom convention used by Snakepit BridgeServer: Any.value is raw JSON bytes.
    return any_pb2.Any(type_url=_STRING_ANY_TYPE_URL, value=_json_bytes(value))


def _encode_parameters(parameters: Mapping[str, Any]) -> Dict[str, any_pb2.Any]:
    return {str(k): _encode_any_json(v) for k, v in parameters.items()}


def _encode_metadata(metadata: Optional[Mapping[str, Any]]) -> Dict[str, str]:
    if not metadata:
        return {}
    out: Dict[str, str] = {}
    for k, v in metadata.items():
        if v is None:
            continue
        out[str(k)] = str(v)
    return out


def _encode_binary_parameters(
    binary_parameters: Optional[Mapping[str, bytes]]
) -> Dict[str, bytes]:
    if not binary_parameters:
        return {}
    out: Dict[str, bytes] = {}
    for k, v in binary_parameters.items():
        if not isinstance(v, (bytes, bytearray, memoryview)):
            raise TypeError(f"binary_parameters[{k!r}] must be bytes-like, got {type(v).__name__}")
        out[str(k)] = bytes(v)
    return out


def _decode_any_json(any_msg: any_pb2.Any) -> Any:
    if not any_msg or not any_msg.value:
        return None
    raw = any_msg.value
    if isinstance(raw, str):
        raw_bytes = raw.encode("utf-8")
    else:
        raw_bytes = raw
    try:
        return json.loads(raw_bytes.decode("utf-8"))
    except Exception:
        # Best-effort fallback: return raw bytes
        return raw_bytes


def _decode_chunk_data(data: bytes) -> Any:
    if not data:
        return {}
    try:
        return json.loads(data.decode("utf-8"))
    except Exception:
        return data


def _normalize_chunk_payload(chunk: pb2.ToolChunk) -> Dict[str, Any]:
    decoded = _decode_chunk_data(chunk.data)

    if isinstance(decoded, dict):
        payload: Dict[str, Any] = dict(decoded)
    else:
        payload = {"data": decoded}

    payload["is_final"] = bool(chunk.is_final)

    meta = dict(chunk.metadata) if getattr(chunk, "metadata", None) else {}
    if meta:
        payload["_metadata"] = meta

    if getattr(chunk, "chunk_id", ""):
        payload["_chunk_id"] = chunk.chunk_id

    return payload


def _new_correlation_id() -> str:
    if _telemetry and hasattr(_telemetry, "new_correlation_id"):
        return _telemetry.new_correlation_id()
    return uuid.uuid4().hex


def _get_correlation_id() -> Optional[str]:
    if _telemetry and hasattr(_telemetry, "get_correlation_id"):
        return _telemetry.get_correlation_id()
    return _fallback_correlation_id.get()


def _set_correlation_id(value: str):
    if _telemetry and hasattr(_telemetry, "set_correlation_id"):
        return _telemetry.set_correlation_id(value)
    return _fallback_correlation_id.set(value)


def _reset_correlation_id(token) -> None:
    if _telemetry and hasattr(_telemetry, "reset_correlation_id"):
        _telemetry.reset_correlation_id(token)
        return
    if token is not None:
        _fallback_correlation_id.reset(token)


def _build_call_metadata(correlation_id: str) -> list[Tuple[str, str]]:
    metadata: list[Tuple[str, str]] = []
    if _telemetry and hasattr(_telemetry, "outgoing_metadata"):
        metadata = list(_telemetry.outgoing_metadata([]))

    metadata = [(k, v) for (k, v) in metadata if k.lower() != _CORRELATION_HEADER]
    metadata.append((_CORRELATION_HEADER, correlation_id))
    return metadata


class BridgeClient:
    """High-level BridgeService client."""

    def __init__(
        self,
        address: Optional[str] = None,
        *,
        channel: Optional[grpc.Channel] = None,
        stub: Optional[pb2_grpc.BridgeServiceStub] = None,
        default_timeout_s: Optional[float] = None,
    ) -> None:
        if stub is not None:
            self._stub = stub
            self._channel = channel
            self._address = address or ""
            self._default_timeout_s = default_timeout_s
            return

        if not address and channel is None:
            raise ValueError("BridgeClient requires either address, channel, or stub")

        self._address = address or ""
        self._channel = channel or grpc.insecure_channel(self._address)
        self._stub = pb2_grpc.BridgeServiceStub(self._channel)
        self._default_timeout_s = default_timeout_s

    @property
    def stub(self) -> pb2_grpc.BridgeServiceStub:
        return self._stub

    def close(self) -> None:
        chan = self._channel
        if chan is not None:
            try:
                chan.close()
            except Exception:
                pass

    def execute_tool(
        self,
        session_id: str,
        tool_name: str,
        parameters: Optional[Mapping[str, Any]] = None,
        *,
        request_metadata: Optional[Mapping[str, Any]] = None,
        binary_parameters: Optional[Mapping[str, bytes]] = None,
        correlation_id: Optional[str] = None,
        timeout_s: Optional[float] = None,
    ) -> Any:
        """Unary tool execution via ExecuteTool."""
        correlation = correlation_id or _get_correlation_id() or _new_correlation_id()
        token = _set_correlation_id(correlation)
        try:
            req_meta = _encode_metadata(request_metadata)
            req_meta.setdefault("correlation_id", correlation)

            req = pb2.ExecuteToolRequest(
                session_id=session_id,
                tool_name=tool_name,
                parameters=_encode_parameters(parameters or {}),
                metadata=req_meta,
                stream=False,
                binary_parameters=_encode_binary_parameters(binary_parameters),
            )

            call_md = _build_call_metadata(correlation)
            resp = self._stub.ExecuteTool(
                req, metadata=call_md, timeout=timeout_s or self._default_timeout_s
            )

            if not resp.success:
                raise RuntimeError(resp.error_message or "ExecuteTool failed")

            decoded = _decode_any_json(resp.result)
            if getattr(resp, "binary_result", None):
                return {"result": decoded, "binary_result": resp.binary_result, "metadata": dict(resp.metadata)}
            return decoded
        finally:
            _reset_correlation_id(token)

    def execute_streaming_tool(
        self,
        session_id: str,
        tool_name: str,
        parameters: Optional[Mapping[str, Any]] = None,
        *,
        request_metadata: Optional[Mapping[str, Any]] = None,
        binary_parameters: Optional[Mapping[str, bytes]] = None,
        correlation_id: Optional[str] = None,
        timeout_s: Optional[float] = None,
    ) -> Iterator[Dict[str, Any]]:
        """Server-streaming tool execution via ExecuteStreamingTool."""
        correlation = correlation_id or _get_correlation_id() or _new_correlation_id()
        token = _set_correlation_id(correlation)

        req_meta = _encode_metadata(request_metadata)
        req_meta.setdefault("correlation_id", correlation)

        req = pb2.ExecuteToolRequest(
            session_id=session_id,
            tool_name=tool_name,
            parameters=_encode_parameters(parameters or {}),
            metadata=req_meta,
            # Field exists but ExecuteStreamingTool RPC is authoritative.
            stream=True,
            binary_parameters=_encode_binary_parameters(binary_parameters),
        )

        call_md = _build_call_metadata(correlation)
        call = None
        try:
            call = self._stub.ExecuteStreamingTool(
                req, metadata=call_md, timeout=timeout_s or self._default_timeout_s
            )

            for chunk in call:
                payload = _normalize_chunk_payload(chunk)
                yield payload
                if chunk.is_final:
                    break
        finally:
            if call is not None and hasattr(call, "cancel"):
                try:
                    call.cancel()
                except Exception:
                    pass
            _reset_correlation_id(token)
