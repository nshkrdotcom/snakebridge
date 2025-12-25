"""SnakeBridge bridge for difflib.

Auto-generated bridge for type conversion (bytes <-> base64).
"""
import base64
import difflib

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

def IS_CHARACTER_JUNK(ch, ws=_MISSING):
    """Wrapper for difflib.IS_CHARACTER_JUNK with type conversion."""
    args_list = [ch]
    call_kwargs = {}
    if ws is not _MISSING:
        call_kwargs["ws"] = ws
    result = difflib.IS_CHARACTER_JUNK(*args_list, **call_kwargs)
    return _serialize(result)

def IS_LINE_JUNK(line, pat=_MISSING):
    """Wrapper for difflib.IS_LINE_JUNK with type conversion."""
    args_list = [line]
    call_kwargs = {}
    if pat is not _MISSING:
        call_kwargs["pat"] = pat
    result = difflib.IS_LINE_JUNK(*args_list, **call_kwargs)
    return _serialize(result)

def context_diff(a, b, fromfile=_MISSING, tofile=_MISSING, fromfiledate=_MISSING, tofiledate=_MISSING, n=_MISSING, lineterm=_MISSING):
    """Wrapper for difflib.context_diff with type conversion."""
    args_list = [a, b]
    call_kwargs = {}
    if fromfile is not _MISSING:
        call_kwargs["fromfile"] = fromfile
    if tofile is not _MISSING:
        call_kwargs["tofile"] = tofile
    if fromfiledate is not _MISSING:
        call_kwargs["fromfiledate"] = fromfiledate
    if tofiledate is not _MISSING:
        call_kwargs["tofiledate"] = tofiledate
    if n is not _MISSING:
        call_kwargs["n"] = n
    if lineterm is not _MISSING:
        call_kwargs["lineterm"] = lineterm
    result = difflib.context_diff(*args_list, **call_kwargs)
    return _serialize(result)

def diff_bytes(dfunc, a, b, fromfile=_MISSING, tofile=_MISSING, fromfiledate=_MISSING, tofiledate=_MISSING, n=_MISSING, lineterm=_MISSING):
    """Wrapper for difflib.diff_bytes with type conversion."""
    b = _to_bytes(b)
    args_list = [dfunc, a, b]
    call_kwargs = {}
    if fromfile is not _MISSING:
        call_kwargs["fromfile"] = fromfile
    if tofile is not _MISSING:
        call_kwargs["tofile"] = tofile
    if fromfiledate is not _MISSING:
        call_kwargs["fromfiledate"] = fromfiledate
    if tofiledate is not _MISSING:
        call_kwargs["tofiledate"] = tofiledate
    if n is not _MISSING:
        call_kwargs["n"] = n
    if lineterm is not _MISSING:
        call_kwargs["lineterm"] = lineterm
    result = difflib.diff_bytes(*args_list, **call_kwargs)
    return _serialize(result)

def get_close_matches(word, possibilities, n=_MISSING, cutoff=_MISSING):
    """Wrapper for difflib.get_close_matches with type conversion."""
    args_list = [word, possibilities]
    call_kwargs = {}
    if n is not _MISSING:
        call_kwargs["n"] = n
    if cutoff is not _MISSING:
        call_kwargs["cutoff"] = cutoff
    result = difflib.get_close_matches(*args_list, **call_kwargs)
    return _serialize(result)

def ndiff(a, b, linejunk=_MISSING, charjunk=_MISSING):
    """Wrapper for difflib.ndiff with type conversion."""
    args_list = [a, b]
    call_kwargs = {}
    if linejunk is not _MISSING:
        call_kwargs["linejunk"] = linejunk
    if charjunk is not _MISSING:
        call_kwargs["charjunk"] = charjunk
    result = difflib.ndiff(*args_list, **call_kwargs)
    return _serialize(result)

def restore(delta, which):
    """Wrapper for difflib.restore with type conversion."""
    args_list = [delta, which]
    call_kwargs = {}
    result = difflib.restore(*args_list, **call_kwargs)
    return _serialize(result)

def unified_diff(a, b, fromfile=_MISSING, tofile=_MISSING, fromfiledate=_MISSING, tofiledate=_MISSING, n=_MISSING, lineterm=_MISSING):
    """Wrapper for difflib.unified_diff with type conversion."""
    args_list = [a, b]
    call_kwargs = {}
    if fromfile is not _MISSING:
        call_kwargs["fromfile"] = fromfile
    if tofile is not _MISSING:
        call_kwargs["tofile"] = tofile
    if fromfiledate is not _MISSING:
        call_kwargs["fromfiledate"] = fromfiledate
    if tofiledate is not _MISSING:
        call_kwargs["tofiledate"] = tofiledate
    if n is not _MISSING:
        call_kwargs["n"] = n
    if lineterm is not _MISSING:
        call_kwargs["lineterm"] = lineterm
    result = difflib.unified_diff(*args_list, **call_kwargs)
    return _serialize(result)
