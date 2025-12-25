"""SnakeBridge bridge for base64.

Auto-generated bridge for type conversion (bytes <-> base64).
"""
import base64
import base64

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

def a85decode(b, *, foldspaces=_MISSING, adobe=_MISSING, ignorechars=_MISSING):
    """Wrapper for base64.a85decode with type conversion."""
    b = _to_bytes_raw(b)
    args_list = [b]
    call_kwargs = {}
    if foldspaces is not _MISSING:
        call_kwargs["foldspaces"] = foldspaces
    if adobe is not _MISSING:
        call_kwargs["adobe"] = adobe
    if ignorechars is not _MISSING:
        call_kwargs["ignorechars"] = ignorechars
    result = base64.a85decode(*args_list, **call_kwargs)
    return _serialize(result)

def a85encode(b, *, foldspaces=_MISSING, wrapcol=_MISSING, pad=_MISSING, adobe=_MISSING):
    """Wrapper for base64.a85encode with type conversion."""
    b = _to_bytes(b)
    args_list = [b]
    call_kwargs = {}
    if foldspaces is not _MISSING:
        call_kwargs["foldspaces"] = foldspaces
    if wrapcol is not _MISSING:
        call_kwargs["wrapcol"] = wrapcol
    if pad is not _MISSING:
        call_kwargs["pad"] = pad
    if adobe is not _MISSING:
        call_kwargs["adobe"] = adobe
    result = base64.a85encode(*args_list, **call_kwargs)
    return _serialize(result)

def b16decode(s, casefold=_MISSING):
    """Wrapper for base64.b16decode with type conversion."""
    s = _to_bytes_raw(s)
    args_list = [s]
    call_kwargs = {}
    if casefold is not _MISSING:
        call_kwargs["casefold"] = casefold
    result = base64.b16decode(*args_list, **call_kwargs)
    return _serialize(result)

def b16encode(s):
    """Wrapper for base64.b16encode with type conversion."""
    s = _to_bytes(s)
    args_list = [s]
    call_kwargs = {}
    result = base64.b16encode(*args_list, **call_kwargs)
    return _serialize(result)

def b32decode(s, casefold=_MISSING, map01=_MISSING):
    """Wrapper for base64.b32decode with type conversion."""
    s = _to_bytes_raw(s)
    args_list = [s]
    call_kwargs = {}
    if casefold is not _MISSING:
        call_kwargs["casefold"] = casefold
    if map01 is not _MISSING:
        call_kwargs["map01"] = map01
    result = base64.b32decode(*args_list, **call_kwargs)
    return _serialize(result)

def b32encode(s):
    """Wrapper for base64.b32encode with type conversion."""
    s = _to_bytes(s)
    args_list = [s]
    call_kwargs = {}
    result = base64.b32encode(*args_list, **call_kwargs)
    return _serialize(result)

def b32hexdecode(s, casefold=_MISSING):
    """Wrapper for base64.b32hexdecode with type conversion."""
    s = _to_bytes_raw(s)
    args_list = [s]
    call_kwargs = {}
    if casefold is not _MISSING:
        call_kwargs["casefold"] = casefold
    result = base64.b32hexdecode(*args_list, **call_kwargs)
    return _serialize(result)

def b32hexencode(s):
    """Wrapper for base64.b32hexencode with type conversion."""
    s = _to_bytes(s)
    args_list = [s]
    call_kwargs = {}
    result = base64.b32hexencode(*args_list, **call_kwargs)
    return _serialize(result)

def b64decode(s, altchars=_MISSING, validate=_MISSING):
    """Wrapper for base64.b64decode with type conversion."""
    s = _to_bytes_raw(s)
    args_list = [s]
    call_kwargs = {}
    if altchars is not _MISSING:
        call_kwargs["altchars"] = altchars
    if validate is not _MISSING:
        call_kwargs["validate"] = validate
    result = base64.b64decode(*args_list, **call_kwargs)
    return _serialize(result)

def b64encode(s, altchars=_MISSING):
    """Wrapper for base64.b64encode with type conversion."""
    s = _to_bytes(s)
    args_list = [s]
    call_kwargs = {}
    if altchars is not _MISSING:
        call_kwargs["altchars"] = altchars
    result = base64.b64encode(*args_list, **call_kwargs)
    return _serialize(result)

def b85decode(b):
    """Wrapper for base64.b85decode with type conversion."""
    b = _to_bytes_raw(b)
    args_list = [b]
    call_kwargs = {}
    result = base64.b85decode(*args_list, **call_kwargs)
    return _serialize(result)

def b85encode(b, pad=_MISSING):
    """Wrapper for base64.b85encode with type conversion."""
    b = _to_bytes(b)
    args_list = [b]
    call_kwargs = {}
    if pad is not _MISSING:
        call_kwargs["pad"] = pad
    result = base64.b85encode(*args_list, **call_kwargs)
    return _serialize(result)

def decode(input, output):
    """Wrapper for base64.decode with type conversion."""
    args_list = [input, output]
    call_kwargs = {}
    result = base64.decode(*args_list, **call_kwargs)
    return _serialize(result)

def decodebytes(s):
    """Wrapper for base64.decodebytes with type conversion."""
    s = _to_bytes_raw(s)
    args_list = [s]
    call_kwargs = {}
    result = base64.decodebytes(*args_list, **call_kwargs)
    return _serialize(result)

def encode(input, output):
    """Wrapper for base64.encode with type conversion."""
    args_list = [input, output]
    call_kwargs = {}
    result = base64.encode(*args_list, **call_kwargs)
    return _serialize(result)

def encodebytes(s):
    """Wrapper for base64.encodebytes with type conversion."""
    s = _to_bytes(s)
    args_list = [s]
    call_kwargs = {}
    result = base64.encodebytes(*args_list, **call_kwargs)
    return _serialize(result)

def main():
    """Wrapper for base64.main with type conversion."""
    args_list = []
    call_kwargs = {}
    result = base64.main(*args_list, **call_kwargs)
    return _serialize(result)

def standard_b64decode(s):
    """Wrapper for base64.standard_b64decode with type conversion."""
    s = _to_bytes_raw(s)
    args_list = [s]
    call_kwargs = {}
    result = base64.standard_b64decode(*args_list, **call_kwargs)
    return _serialize(result)

def standard_b64encode(s):
    """Wrapper for base64.standard_b64encode with type conversion."""
    s = _to_bytes(s)
    args_list = [s]
    call_kwargs = {}
    result = base64.standard_b64encode(*args_list, **call_kwargs)
    return _serialize(result)

def urlsafe_b64decode(s):
    """Wrapper for base64.urlsafe_b64decode with type conversion."""
    s = _to_bytes_raw(s)
    args_list = [s]
    call_kwargs = {}
    result = base64.urlsafe_b64decode(*args_list, **call_kwargs)
    return _serialize(result)

def urlsafe_b64encode(s):
    """Wrapper for base64.urlsafe_b64encode with type conversion."""
    s = _to_bytes(s)
    args_list = [s]
    call_kwargs = {}
    result = base64.urlsafe_b64encode(*args_list, **call_kwargs)
    return _serialize(result)
