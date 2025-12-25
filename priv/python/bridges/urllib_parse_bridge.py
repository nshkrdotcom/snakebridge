"""SnakeBridge bridge for urllib.parse.

Auto-generated bridge for type conversion (bytes <-> base64).
"""
import base64
import urllib.parse

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

def clear_cache():
    """Wrapper for urllib.parse.clear_cache with type conversion."""
    args_list = []
    call_kwargs = {}
    result = urllib.parse.clear_cache(*args_list, **call_kwargs)
    return _serialize(result)

def namedtuple(typename, field_names, *, rename=_MISSING, defaults=_MISSING, module=_MISSING):
    """Wrapper for urllib.parse.namedtuple with type conversion."""
    args_list = [typename, field_names]
    call_kwargs = {}
    if rename is not _MISSING:
        call_kwargs["rename"] = rename
    if defaults is not _MISSING:
        call_kwargs["defaults"] = defaults
    if module is not _MISSING:
        call_kwargs["module"] = module
    result = urllib.parse.namedtuple(*args_list, **call_kwargs)
    return _serialize(result)

def parse_qs(qs, keep_blank_values=_MISSING, strict_parsing=_MISSING, encoding=_MISSING, errors=_MISSING, max_num_fields=_MISSING, separator=_MISSING):
    """Wrapper for urllib.parse.parse_qs with type conversion."""
    args_list = [qs]
    call_kwargs = {}
    if keep_blank_values is not _MISSING:
        call_kwargs["keep_blank_values"] = keep_blank_values
    if strict_parsing is not _MISSING:
        call_kwargs["strict_parsing"] = strict_parsing
    if encoding is not _MISSING:
        call_kwargs["encoding"] = encoding
    if errors is not _MISSING:
        call_kwargs["errors"] = errors
    if max_num_fields is not _MISSING:
        call_kwargs["max_num_fields"] = max_num_fields
    if separator is not _MISSING:
        call_kwargs["separator"] = separator
    result = urllib.parse.parse_qs(*args_list, **call_kwargs)
    return _serialize(result)

def parse_qsl(qs, keep_blank_values=_MISSING, strict_parsing=_MISSING, encoding=_MISSING, errors=_MISSING, max_num_fields=_MISSING, separator=_MISSING):
    """Wrapper for urllib.parse.parse_qsl with type conversion."""
    args_list = [qs]
    call_kwargs = {}
    if keep_blank_values is not _MISSING:
        call_kwargs["keep_blank_values"] = keep_blank_values
    if strict_parsing is not _MISSING:
        call_kwargs["strict_parsing"] = strict_parsing
    if encoding is not _MISSING:
        call_kwargs["encoding"] = encoding
    if errors is not _MISSING:
        call_kwargs["errors"] = errors
    if max_num_fields is not _MISSING:
        call_kwargs["max_num_fields"] = max_num_fields
    if separator is not _MISSING:
        call_kwargs["separator"] = separator
    result = urllib.parse.parse_qsl(*args_list, **call_kwargs)
    return _serialize(result)

def quote(string, safe=_MISSING, encoding=_MISSING, errors=_MISSING):
    """Wrapper for urllib.parse.quote with type conversion."""
    args_list = [string]
    call_kwargs = {}
    if safe is not _MISSING:
        call_kwargs["safe"] = safe
    if encoding is not _MISSING:
        call_kwargs["encoding"] = encoding
    if errors is not _MISSING:
        call_kwargs["errors"] = errors
    result = urllib.parse.quote(*args_list, **call_kwargs)
    return _serialize(result)

def quote_from_bytes(bs, safe=_MISSING):
    """Wrapper for urllib.parse.quote_from_bytes with type conversion."""
    bs = _to_bytes(bs)
    args_list = [bs]
    call_kwargs = {}
    if safe is not _MISSING:
        call_kwargs["safe"] = safe
    result = urllib.parse.quote_from_bytes(*args_list, **call_kwargs)
    return _serialize(result)

def quote_plus(string, safe=_MISSING, encoding=_MISSING, errors=_MISSING):
    """Wrapper for urllib.parse.quote_plus with type conversion."""
    args_list = [string]
    call_kwargs = {}
    if safe is not _MISSING:
        call_kwargs["safe"] = safe
    if encoding is not _MISSING:
        call_kwargs["encoding"] = encoding
    if errors is not _MISSING:
        call_kwargs["errors"] = errors
    result = urllib.parse.quote_plus(*args_list, **call_kwargs)
    return _serialize(result)

def splitattr(url):
    """Wrapper for urllib.parse.splitattr with type conversion."""
    args_list = [url]
    call_kwargs = {}
    result = urllib.parse.splitattr(*args_list, **call_kwargs)
    return _serialize(result)

def splithost(url):
    """Wrapper for urllib.parse.splithost with type conversion."""
    args_list = [url]
    call_kwargs = {}
    result = urllib.parse.splithost(*args_list, **call_kwargs)
    return _serialize(result)

def splitnport(host, defport=_MISSING):
    """Wrapper for urllib.parse.splitnport with type conversion."""
    args_list = [host]
    call_kwargs = {}
    if defport is not _MISSING:
        call_kwargs["defport"] = defport
    result = urllib.parse.splitnport(*args_list, **call_kwargs)
    return _serialize(result)

def splitpasswd(user):
    """Wrapper for urllib.parse.splitpasswd with type conversion."""
    args_list = [user]
    call_kwargs = {}
    result = urllib.parse.splitpasswd(*args_list, **call_kwargs)
    return _serialize(result)

def splitport(host):
    """Wrapper for urllib.parse.splitport with type conversion."""
    args_list = [host]
    call_kwargs = {}
    result = urllib.parse.splitport(*args_list, **call_kwargs)
    return _serialize(result)

def splitquery(url):
    """Wrapper for urllib.parse.splitquery with type conversion."""
    args_list = [url]
    call_kwargs = {}
    result = urllib.parse.splitquery(*args_list, **call_kwargs)
    return _serialize(result)

def splittag(url):
    """Wrapper for urllib.parse.splittag with type conversion."""
    args_list = [url]
    call_kwargs = {}
    result = urllib.parse.splittag(*args_list, **call_kwargs)
    return _serialize(result)

def splittype(url):
    """Wrapper for urllib.parse.splittype with type conversion."""
    args_list = [url]
    call_kwargs = {}
    result = urllib.parse.splittype(*args_list, **call_kwargs)
    return _serialize(result)

def splituser(host):
    """Wrapper for urllib.parse.splituser with type conversion."""
    args_list = [host]
    call_kwargs = {}
    result = urllib.parse.splituser(*args_list, **call_kwargs)
    return _serialize(result)

def splitvalue(attr):
    """Wrapper for urllib.parse.splitvalue with type conversion."""
    args_list = [attr]
    call_kwargs = {}
    result = urllib.parse.splitvalue(*args_list, **call_kwargs)
    return _serialize(result)

def to_bytes(url):
    """Wrapper for urllib.parse.to_bytes with type conversion."""
    args_list = [url]
    call_kwargs = {}
    result = urllib.parse.to_bytes(*args_list, **call_kwargs)
    return _serialize(result)

def unquote(string, encoding=_MISSING, errors=_MISSING):
    """Wrapper for urllib.parse.unquote with type conversion."""
    args_list = [string]
    call_kwargs = {}
    if encoding is not _MISSING:
        call_kwargs["encoding"] = encoding
    if errors is not _MISSING:
        call_kwargs["errors"] = errors
    result = urllib.parse.unquote(*args_list, **call_kwargs)
    return _serialize(result)

def unquote_plus(string, encoding=_MISSING, errors=_MISSING):
    """Wrapper for urllib.parse.unquote_plus with type conversion."""
    args_list = [string]
    call_kwargs = {}
    if encoding is not _MISSING:
        call_kwargs["encoding"] = encoding
    if errors is not _MISSING:
        call_kwargs["errors"] = errors
    result = urllib.parse.unquote_plus(*args_list, **call_kwargs)
    return _serialize(result)

def unquote_to_bytes(string):
    """Wrapper for urllib.parse.unquote_to_bytes with type conversion."""
    args_list = [string]
    call_kwargs = {}
    result = urllib.parse.unquote_to_bytes(*args_list, **call_kwargs)
    return _serialize(result)

def unwrap(url):
    """Wrapper for urllib.parse.unwrap with type conversion."""
    args_list = [url]
    call_kwargs = {}
    result = urllib.parse.unwrap(*args_list, **call_kwargs)
    return _serialize(result)

def urldefrag(url):
    """Wrapper for urllib.parse.urldefrag with type conversion."""
    args_list = [url]
    call_kwargs = {}
    result = urllib.parse.urldefrag(*args_list, **call_kwargs)
    return _serialize(result)

def urlencode(query, doseq=_MISSING, safe=_MISSING, encoding=_MISSING, errors=_MISSING, quote_via=_MISSING):
    """Wrapper for urllib.parse.urlencode with type conversion."""
    args_list = [query]
    call_kwargs = {}
    if doseq is not _MISSING:
        call_kwargs["doseq"] = doseq
    if safe is not _MISSING:
        call_kwargs["safe"] = safe
    if encoding is not _MISSING:
        call_kwargs["encoding"] = encoding
    if errors is not _MISSING:
        call_kwargs["errors"] = errors
    if quote_via is not _MISSING:
        call_kwargs["quote_via"] = quote_via
    result = urllib.parse.urlencode(*args_list, **call_kwargs)
    return _serialize(result)

def urljoin(base, url, allow_fragments=_MISSING):
    """Wrapper for urllib.parse.urljoin with type conversion."""
    args_list = [base, url]
    call_kwargs = {}
    if allow_fragments is not _MISSING:
        call_kwargs["allow_fragments"] = allow_fragments
    result = urllib.parse.urljoin(*args_list, **call_kwargs)
    return _serialize(result)

def urlparse(url, scheme=_MISSING, allow_fragments=_MISSING):
    """Wrapper for urllib.parse.urlparse with type conversion."""
    args_list = [url]
    call_kwargs = {}
    if scheme is not _MISSING:
        call_kwargs["scheme"] = scheme
    if allow_fragments is not _MISSING:
        call_kwargs["allow_fragments"] = allow_fragments
    result = urllib.parse.urlparse(*args_list, **call_kwargs)
    return _serialize(result)

def urlunparse(components):
    """Wrapper for urllib.parse.urlunparse with type conversion."""
    args_list = [components]
    call_kwargs = {}
    result = urllib.parse.urlunparse(*args_list, **call_kwargs)
    return _serialize(result)

def urlunsplit(components):
    """Wrapper for urllib.parse.urlunsplit with type conversion."""
    args_list = [components]
    call_kwargs = {}
    result = urllib.parse.urlunsplit(*args_list, **call_kwargs)
    return _serialize(result)
