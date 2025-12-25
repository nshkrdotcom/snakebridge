"""SnakeBridge bridge for hashlib.

Auto-generated bridge for type conversion (bytes <-> base64).
"""
import base64
import hashlib

_MISSING = object()

def _to_bytes(data):
    """Convert input to bytes (handles base64 string or raw bytes)."""
    if data is None:
        return None
    if isinstance(data, bytes):
        return data
    if isinstance(data, str):
        try:
            return base64.b64decode(data)
        except Exception:
            return data.encode('utf-8')
    return bytes(data)

def _to_bytes_raw(data):
    """Convert input to bytes without base64 decoding."""
    if data is None:
        return None
    if isinstance(data, bytes):
        return data
    if isinstance(data, str):
        return data.encode('utf-8')
    return bytes(data)

def _serialize(obj):
    """Convert result to JSON-serializable format."""
    if obj is None:
        return None
    if isinstance(obj, (str, int, float, bool)):
        return obj
    if isinstance(obj, bytes):
        return base64.b64encode(obj).decode('ascii')
    if isinstance(obj, (list, tuple)):
        return [_serialize(x) for x in obj]
    if isinstance(obj, dict):
        return {str(k): _serialize(v) for k, v in obj.items()}
    if hasattr(obj, '__dict__'):
        return {k: _serialize(v) for k, v in obj.__dict__.items() if not k.startswith('_')}
    return str(obj)

def file_digest(fileobj, digest, /, *, _bufsize=_MISSING):
    """Wrapper for hashlib.file_digest with type conversion."""
    if _bufsize is not _MISSING:
        _bufsize = _to_bytes(_bufsize)
    args_list = [fileobj, digest]
    call_kwargs = {}
    if _bufsize is not _MISSING:
        call_kwargs["_bufsize"] = _bufsize
    result = hashlib.file_digest(*args_list, **call_kwargs)
    return _serialize(result)

def new(name, data=_MISSING, **kwargs):
    """Wrapper for hashlib.new with type conversion."""
    if data is not _MISSING:
        data = _to_bytes(data)
    args_list = [name]
    call_kwargs = {}
    if data is not _MISSING:
        call_kwargs["data"] = data
    result = hashlib.new(*args_list, **call_kwargs, **kwargs)
    return _serialize(result)
