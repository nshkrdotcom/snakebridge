"""SnakeBridge bridge for chardet.

Auto-generated bridge for type conversion (bytes <-> base64).
"""
import base64
import chardet

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

def detect(byte_str, should_rename_legacy=_MISSING):
    """Wrapper for chardet.detect with type conversion."""
    byte_str = _to_bytes(byte_str)
    args_list = [byte_str]
    call_kwargs = {}
    if should_rename_legacy is not _MISSING:
        call_kwargs["should_rename_legacy"] = should_rename_legacy
    result = chardet.detect(*args_list, **call_kwargs)
    return _serialize(result)

def detect_all(byte_str, ignore_threshold=_MISSING, should_rename_legacy=_MISSING):
    """Wrapper for chardet.detect_all with type conversion."""
    byte_str = _to_bytes(byte_str)
    args_list = [byte_str]
    call_kwargs = {}
    if ignore_threshold is not _MISSING:
        call_kwargs["ignore_threshold"] = ignore_threshold
    if should_rename_legacy is not _MISSING:
        call_kwargs["should_rename_legacy"] = should_rename_legacy
    result = chardet.detect_all(*args_list, **call_kwargs)
    return _serialize(result)
