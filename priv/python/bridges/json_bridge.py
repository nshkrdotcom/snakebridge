"""SnakeBridge bridge for json.

Auto-generated bridge for type conversion (bytes <-> base64).
"""
import base64
import json

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

def detect_encoding(b):
    """Wrapper for json.detect_encoding with type conversion."""
    b = _to_bytes(b)
    args_list = [b]
    call_kwargs = {}
    result = json.detect_encoding(*args_list, **call_kwargs)
    return _serialize(result)

def dump(obj, fp, *, skipkeys=_MISSING, ensure_ascii=_MISSING, check_circular=_MISSING, allow_nan=_MISSING, cls=_MISSING, indent=_MISSING, separators=_MISSING, default=_MISSING, sort_keys=_MISSING, **kw):
    """Wrapper for json.dump with type conversion."""
    args_list = [obj, fp]
    call_kwargs = {}
    if skipkeys is not _MISSING:
        call_kwargs["skipkeys"] = skipkeys
    if ensure_ascii is not _MISSING:
        call_kwargs["ensure_ascii"] = ensure_ascii
    if check_circular is not _MISSING:
        call_kwargs["check_circular"] = check_circular
    if allow_nan is not _MISSING:
        call_kwargs["allow_nan"] = allow_nan
    if cls is not _MISSING:
        call_kwargs["cls"] = cls
    if indent is not _MISSING:
        call_kwargs["indent"] = indent
    if separators is not _MISSING:
        call_kwargs["separators"] = separators
    if default is not _MISSING:
        call_kwargs["default"] = default
    if sort_keys is not _MISSING:
        call_kwargs["sort_keys"] = sort_keys
    result = json.dump(*args_list, **call_kwargs, **kw)
    return _serialize(result)

def dumps(obj, *, skipkeys=_MISSING, ensure_ascii=_MISSING, check_circular=_MISSING, allow_nan=_MISSING, cls=_MISSING, indent=_MISSING, separators=_MISSING, default=_MISSING, sort_keys=_MISSING, **kw):
    """Wrapper for json.dumps with type conversion."""
    args_list = [obj]
    call_kwargs = {}
    if skipkeys is not _MISSING:
        call_kwargs["skipkeys"] = skipkeys
    if ensure_ascii is not _MISSING:
        call_kwargs["ensure_ascii"] = ensure_ascii
    if check_circular is not _MISSING:
        call_kwargs["check_circular"] = check_circular
    if allow_nan is not _MISSING:
        call_kwargs["allow_nan"] = allow_nan
    if cls is not _MISSING:
        call_kwargs["cls"] = cls
    if indent is not _MISSING:
        call_kwargs["indent"] = indent
    if separators is not _MISSING:
        call_kwargs["separators"] = separators
    if default is not _MISSING:
        call_kwargs["default"] = default
    if sort_keys is not _MISSING:
        call_kwargs["sort_keys"] = sort_keys
    result = json.dumps(*args_list, **call_kwargs, **kw)
    return _serialize(result)

def load(fp, *, cls=_MISSING, object_hook=_MISSING, parse_float=_MISSING, parse_int=_MISSING, parse_constant=_MISSING, object_pairs_hook=_MISSING, **kw):
    """Wrapper for json.load with type conversion."""
    args_list = [fp]
    call_kwargs = {}
    if cls is not _MISSING:
        call_kwargs["cls"] = cls
    if object_hook is not _MISSING:
        call_kwargs["object_hook"] = object_hook
    if parse_float is not _MISSING:
        call_kwargs["parse_float"] = parse_float
    if parse_int is not _MISSING:
        call_kwargs["parse_int"] = parse_int
    if parse_constant is not _MISSING:
        call_kwargs["parse_constant"] = parse_constant
    if object_pairs_hook is not _MISSING:
        call_kwargs["object_pairs_hook"] = object_pairs_hook
    result = json.load(*args_list, **call_kwargs, **kw)
    return _serialize(result)

def loads(s, *, cls=_MISSING, object_hook=_MISSING, parse_float=_MISSING, parse_int=_MISSING, parse_constant=_MISSING, object_pairs_hook=_MISSING, **kw):
    """Wrapper for json.loads with type conversion."""
    s = _to_bytes(s)
    args_list = [s]
    call_kwargs = {}
    if cls is not _MISSING:
        call_kwargs["cls"] = cls
    if object_hook is not _MISSING:
        call_kwargs["object_hook"] = object_hook
    if parse_float is not _MISSING:
        call_kwargs["parse_float"] = parse_float
    if parse_int is not _MISSING:
        call_kwargs["parse_int"] = parse_int
    if parse_constant is not _MISSING:
        call_kwargs["parse_constant"] = parse_constant
    if object_pairs_hook is not _MISSING:
        call_kwargs["object_pairs_hook"] = object_pairs_hook
    result = json.loads(*args_list, **call_kwargs, **kw)
    return _serialize(result)
