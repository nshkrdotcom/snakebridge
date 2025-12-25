"""SnakeBridge bridge for requests.

Auto-generated bridge for type conversion (bytes <-> base64).
"""
import base64
import requests

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

def check_compatibility(urllib3_version, chardet_version, charset_normalizer_version):
    """Wrapper for requests.check_compatibility with type conversion."""
    args_list = [urllib3_version, chardet_version, charset_normalizer_version]
    call_kwargs = {}
    result = requests.check_compatibility(*args_list, **call_kwargs)
    return _serialize(result)

def delete(url, **kwargs):
    """Wrapper for requests.delete with type conversion."""
    args_list = [url]
    call_kwargs = {}
    result = requests.delete(*args_list, **call_kwargs, **kwargs)
    return _serialize(result)

def get(url, params=_MISSING, **kwargs):
    """Wrapper for requests.get with type conversion."""
    args_list = [url]
    call_kwargs = {}
    if params is not _MISSING:
        call_kwargs["params"] = params
    result = requests.get(*args_list, **call_kwargs, **kwargs)
    return _serialize(result)

def head(url, **kwargs):
    """Wrapper for requests.head with type conversion."""
    args_list = [url]
    call_kwargs = {}
    result = requests.head(*args_list, **call_kwargs, **kwargs)
    return _serialize(result)

def options(url, **kwargs):
    """Wrapper for requests.options with type conversion."""
    args_list = [url]
    call_kwargs = {}
    result = requests.options(*args_list, **call_kwargs, **kwargs)
    return _serialize(result)

def patch(url, data=_MISSING, **kwargs):
    """Wrapper for requests.patch with type conversion."""
    if data is not _MISSING:
        data = _to_bytes(data)
    args_list = [url]
    call_kwargs = {}
    if data is not _MISSING:
        call_kwargs["data"] = data
    result = requests.patch(*args_list, **call_kwargs, **kwargs)
    return _serialize(result)

def post(url, data=_MISSING, json=_MISSING, **kwargs):
    """Wrapper for requests.post with type conversion."""
    if data is not _MISSING:
        data = _to_bytes(data)
    args_list = [url]
    call_kwargs = {}
    if data is not _MISSING:
        call_kwargs["data"] = data
    if json is not _MISSING:
        call_kwargs["json"] = json
    result = requests.post(*args_list, **call_kwargs, **kwargs)
    return _serialize(result)

def put(url, data=_MISSING, **kwargs):
    """Wrapper for requests.put with type conversion."""
    if data is not _MISSING:
        data = _to_bytes(data)
    args_list = [url]
    call_kwargs = {}
    if data is not _MISSING:
        call_kwargs["data"] = data
    result = requests.put(*args_list, **call_kwargs, **kwargs)
    return _serialize(result)

def request(method, url, **kwargs):
    """Wrapper for requests.request with type conversion."""
    args_list = [method, url]
    call_kwargs = {}
    result = requests.request(*args_list, **call_kwargs, **kwargs)
    return _serialize(result)

def session():
    """Wrapper for requests.session with type conversion."""
    args_list = []
    call_kwargs = {}
    result = requests.session(*args_list, **call_kwargs)
    return _serialize(result)
