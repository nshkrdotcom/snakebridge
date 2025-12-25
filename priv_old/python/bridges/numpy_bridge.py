"""SnakeBridge bridge for numpy.

Auto-generated bridge for type conversion (bytes <-> base64).
"""
import base64
import numpy

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

def load(file, mmap_mode=_MISSING, allow_pickle=_MISSING, fix_imports=_MISSING, encoding=_MISSING, *, max_header_size=_MISSING):
    """Wrapper for numpy.load with type conversion."""
    args_list = [file]
    call_kwargs = {}
    if mmap_mode is not _MISSING:
        call_kwargs["mmap_mode"] = mmap_mode
    if allow_pickle is not _MISSING:
        call_kwargs["allow_pickle"] = allow_pickle
    if fix_imports is not _MISSING:
        call_kwargs["fix_imports"] = fix_imports
    if encoding is not _MISSING:
        call_kwargs["encoding"] = encoding
    if max_header_size is not _MISSING:
        call_kwargs["max_header_size"] = max_header_size
    result = numpy.load(*args_list, **call_kwargs)
    return _serialize(result)

def broadcast_shapes(*args):
    """Wrapper for numpy.broadcast_shapes with type conversion."""
    args_list = []
    call_kwargs = {}
    result = numpy.broadcast_shapes(*args_list, *args, **call_kwargs)
    return _serialize(result)

def isfortran(a):
    """Wrapper for numpy.isfortran with type conversion."""
    args_list = [a]
    call_kwargs = {}
    result = numpy.isfortran(*args_list, **call_kwargs)
    return _serialize(result)

def isdtype(dtype, kind):
    """Wrapper for numpy.isdtype with type conversion."""
    args_list = [dtype, kind]
    call_kwargs = {}
    result = numpy.isdtype(*args_list, **call_kwargs)
    return _serialize(result)

def trapz(y, x=_MISSING, dx=_MISSING, axis=_MISSING):
    """Wrapper for numpy.trapz with type conversion."""
    args_list = [y]
    call_kwargs = {}
    if x is not _MISSING:
        call_kwargs["x"] = x
    if dx is not _MISSING:
        call_kwargs["dx"] = dx
    if axis is not _MISSING:
        call_kwargs["axis"] = axis
    result = numpy.trapz(*args_list, **call_kwargs)
    return _serialize(result)

def kaiser(M, beta):
    """Wrapper for numpy.kaiser with type conversion."""
    args_list = [M, beta]
    call_kwargs = {}
    result = numpy.kaiser(*args_list, **call_kwargs)
    return _serialize(result)

def row_stack(tup, *, dtype=_MISSING, casting=_MISSING):
    """Wrapper for numpy.row_stack with type conversion."""
    args_list = [tup]
    call_kwargs = {}
    if dtype is not _MISSING:
        call_kwargs["dtype"] = dtype
    if casting is not _MISSING:
        call_kwargs["casting"] = casting
    result = numpy.row_stack(*args_list, **call_kwargs)
    return _serialize(result)

def get_printoptions():
    """Wrapper for numpy.get_printoptions with type conversion."""
    args_list = []
    call_kwargs = {}
    result = numpy.get_printoptions(*args_list, **call_kwargs)
    return _serialize(result)

def show_runtime():
    """Wrapper for numpy.show_runtime with type conversion."""
    args_list = []
    call_kwargs = {}
    result = numpy.show_runtime(*args_list, **call_kwargs)
    return _serialize(result)

def full(shape, fill_value, dtype=_MISSING, order=_MISSING, *, device=_MISSING, like=_MISSING):
    """Wrapper for numpy.full with type conversion."""
    args_list = [shape, fill_value]
    call_kwargs = {}
    if dtype is not _MISSING:
        call_kwargs["dtype"] = dtype
    if order is not _MISSING:
        call_kwargs["order"] = order
    if device is not _MISSING:
        call_kwargs["device"] = device
    if like is not _MISSING:
        call_kwargs["like"] = like
    result = numpy.full(*args_list, **call_kwargs)
    return _serialize(result)

def ones(shape, dtype=_MISSING, order=_MISSING, *, device=_MISSING, like=_MISSING):
    """Wrapper for numpy.ones with type conversion."""
    args_list = [shape]
    call_kwargs = {}
    if dtype is not _MISSING:
        call_kwargs["dtype"] = dtype
    if order is not _MISSING:
        call_kwargs["order"] = order
    if device is not _MISSING:
        call_kwargs["device"] = device
    if like is not _MISSING:
        call_kwargs["like"] = like
    result = numpy.ones(*args_list, **call_kwargs)
    return _serialize(result)

def tril_indices(n, k=_MISSING, m=_MISSING):
    """Wrapper for numpy.tril_indices with type conversion."""
    args_list = [n]
    call_kwargs = {}
    if k is not _MISSING:
        call_kwargs["k"] = k
    if m is not _MISSING:
        call_kwargs["m"] = m
    result = numpy.tril_indices(*args_list, **call_kwargs)
    return _serialize(result)

def mask_indices(n, mask_func, k=_MISSING):
    """Wrapper for numpy.mask_indices with type conversion."""
    args_list = [n, mask_func]
    call_kwargs = {}
    if k is not _MISSING:
        call_kwargs["k"] = k
    result = numpy.mask_indices(*args_list, **call_kwargs)
    return _serialize(result)

def loadtxt(fname, dtype=_MISSING, comments=_MISSING, delimiter=_MISSING, converters=_MISSING, skiprows=_MISSING, usecols=_MISSING, unpack=_MISSING, ndmin=_MISSING, encoding=_MISSING, max_rows=_MISSING, *, quotechar=_MISSING, like=_MISSING):
    """Wrapper for numpy.loadtxt with type conversion."""
    args_list = [fname]
    call_kwargs = {}
    if dtype is not _MISSING:
        call_kwargs["dtype"] = dtype
    if comments is not _MISSING:
        call_kwargs["comments"] = comments
    if delimiter is not _MISSING:
        call_kwargs["delimiter"] = delimiter
    if converters is not _MISSING:
        call_kwargs["converters"] = converters
    if skiprows is not _MISSING:
        call_kwargs["skiprows"] = skiprows
    if usecols is not _MISSING:
        call_kwargs["usecols"] = usecols
    if unpack is not _MISSING:
        call_kwargs["unpack"] = unpack
    if ndmin is not _MISSING:
        call_kwargs["ndmin"] = ndmin
    if encoding is not _MISSING:
        call_kwargs["encoding"] = encoding
    if max_rows is not _MISSING:
        call_kwargs["max_rows"] = max_rows
    if quotechar is not _MISSING:
        call_kwargs["quotechar"] = quotechar
    if like is not _MISSING:
        call_kwargs["like"] = like
    result = numpy.loadtxt(*args_list, **call_kwargs)
    return _serialize(result)

def require(a, dtype=_MISSING, requirements=_MISSING, *, like=_MISSING):
    """Wrapper for numpy.require with type conversion."""
    args_list = [a]
    call_kwargs = {}
    if dtype is not _MISSING:
        call_kwargs["dtype"] = dtype
    if requirements is not _MISSING:
        call_kwargs["requirements"] = requirements
    if like is not _MISSING:
        call_kwargs["like"] = like
    result = numpy.require(*args_list, **call_kwargs)
    return _serialize(result)

def mintypecode(typechars, typeset=_MISSING, default=_MISSING):
    """Wrapper for numpy.mintypecode with type conversion."""
    args_list = [typechars]
    call_kwargs = {}
    if typeset is not _MISSING:
        call_kwargs["typeset"] = typeset
    if default is not _MISSING:
        call_kwargs["default"] = default
    result = numpy.mintypecode(*args_list, **call_kwargs)
    return _serialize(result)

def show_config(mode=_MISSING):
    """Wrapper for numpy.show_config with type conversion."""
    args_list = []
    call_kwargs = {}
    if mode is not _MISSING:
        call_kwargs["mode"] = mode
    result = numpy.show_config(*args_list, **call_kwargs)
    return _serialize(result)

def isscalar(element):
    """Wrapper for numpy.isscalar with type conversion."""
    args_list = [element]
    call_kwargs = {}
    result = numpy.isscalar(*args_list, **call_kwargs)
    return _serialize(result)

def asmatrix(data, dtype=_MISSING):
    """Wrapper for numpy.asmatrix with type conversion."""
    args_list = [data]
    call_kwargs = {}
    if dtype is not _MISSING:
        call_kwargs["dtype"] = dtype
    result = numpy.asmatrix(*args_list, **call_kwargs)
    return _serialize(result)

def seterrcall(func):
    """Wrapper for numpy.seterrcall with type conversion."""
    args_list = [func]
    call_kwargs = {}
    result = numpy.seterrcall(*args_list, **call_kwargs)
    return _serialize(result)

def getbufsize():
    """Wrapper for numpy.getbufsize with type conversion."""
    args_list = []
    call_kwargs = {}
    result = numpy.getbufsize(*args_list, **call_kwargs)
    return _serialize(result)

def setbufsize(size):
    """Wrapper for numpy.setbufsize with type conversion."""
    args_list = [size]
    call_kwargs = {}
    result = numpy.setbufsize(*args_list, **call_kwargs)
    return _serialize(result)

def info(object=_MISSING, maxwidth=_MISSING, output=_MISSING, toplevel=_MISSING):
    """Wrapper for numpy.info with type conversion."""
    args_list = []
    call_kwargs = {}
    if object is not _MISSING:
        call_kwargs["object"] = object
    if maxwidth is not _MISSING:
        call_kwargs["maxwidth"] = maxwidth
    if output is not _MISSING:
        call_kwargs["output"] = output
    if toplevel is not _MISSING:
        call_kwargs["toplevel"] = toplevel
    result = numpy.info(*args_list, **call_kwargs)
    return _serialize(result)

def hanning(M):
    """Wrapper for numpy.hanning with type conversion."""
    args_list = [M]
    call_kwargs = {}
    result = numpy.hanning(*args_list, **call_kwargs)
    return _serialize(result)

def geterr():
    """Wrapper for numpy.geterr with type conversion."""
    args_list = []
    call_kwargs = {}
    result = numpy.geterr(*args_list, **call_kwargs)
    return _serialize(result)

def base_repr(number, base=_MISSING, padding=_MISSING):
    """Wrapper for numpy.base_repr with type conversion."""
    args_list = [number]
    call_kwargs = {}
    if base is not _MISSING:
        call_kwargs["base"] = base
    if padding is not _MISSING:
        call_kwargs["padding"] = padding
    result = numpy.base_repr(*args_list, **call_kwargs)
    return _serialize(result)

def identity(n, dtype=_MISSING, *, like=_MISSING):
    """Wrapper for numpy.identity with type conversion."""
    args_list = [n]
    call_kwargs = {}
    if dtype is not _MISSING:
        call_kwargs["dtype"] = dtype
    if like is not _MISSING:
        call_kwargs["like"] = like
    result = numpy.identity(*args_list, **call_kwargs)
    return _serialize(result)

def binary_repr(num, width=_MISSING):
    """Wrapper for numpy.binary_repr with type conversion."""
    args_list = [num]
    call_kwargs = {}
    if width is not _MISSING:
        call_kwargs["width"] = width
    result = numpy.binary_repr(*args_list, **call_kwargs)
    return _serialize(result)

def triu_indices(n, k=_MISSING, m=_MISSING):
    """Wrapper for numpy.triu_indices with type conversion."""
    args_list = [n]
    call_kwargs = {}
    if k is not _MISSING:
        call_kwargs["k"] = k
    if m is not _MISSING:
        call_kwargs["m"] = m
    result = numpy.triu_indices(*args_list, **call_kwargs)
    return _serialize(result)

def asarray_chkfinite(a, dtype=_MISSING, order=_MISSING):
    """Wrapper for numpy.asarray_chkfinite with type conversion."""
    args_list = [a]
    call_kwargs = {}
    if dtype is not _MISSING:
        call_kwargs["dtype"] = dtype
    if order is not _MISSING:
        call_kwargs["order"] = order
    result = numpy.asarray_chkfinite(*args_list, **call_kwargs)
    return _serialize(result)

def format_float_scientific(x, precision=_MISSING, unique=_MISSING, trim=_MISSING, sign=_MISSING, pad_left=_MISSING, exp_digits=_MISSING, min_digits=_MISSING):
    """Wrapper for numpy.format_float_scientific with type conversion."""
    args_list = [x]
    call_kwargs = {}
    if precision is not _MISSING:
        call_kwargs["precision"] = precision
    if unique is not _MISSING:
        call_kwargs["unique"] = unique
    if trim is not _MISSING:
        call_kwargs["trim"] = trim
    if sign is not _MISSING:
        call_kwargs["sign"] = sign
    if pad_left is not _MISSING:
        call_kwargs["pad_left"] = pad_left
    if exp_digits is not _MISSING:
        call_kwargs["exp_digits"] = exp_digits
    if min_digits is not _MISSING:
        call_kwargs["min_digits"] = min_digits
    result = numpy.format_float_scientific(*args_list, **call_kwargs)
    return _serialize(result)

def bmat(obj, ldict=_MISSING, gdict=_MISSING):
    """Wrapper for numpy.bmat with type conversion."""
    args_list = [obj]
    call_kwargs = {}
    if ldict is not _MISSING:
        call_kwargs["ldict"] = ldict
    if gdict is not _MISSING:
        call_kwargs["gdict"] = gdict
    result = numpy.bmat(*args_list, **call_kwargs)
    return _serialize(result)

def geterrcall():
    """Wrapper for numpy.geterrcall with type conversion."""
    args_list = []
    call_kwargs = {}
    result = numpy.geterrcall(*args_list, **call_kwargs)
    return _serialize(result)

def iterable(y):
    """Wrapper for numpy.iterable with type conversion."""
    args_list = [y]
    call_kwargs = {}
    result = numpy.iterable(*args_list, **call_kwargs)
    return _serialize(result)

def format_float_positional(x, precision=_MISSING, unique=_MISSING, fractional=_MISSING, trim=_MISSING, sign=_MISSING, pad_left=_MISSING, pad_right=_MISSING, min_digits=_MISSING):
    """Wrapper for numpy.format_float_positional with type conversion."""
    args_list = [x]
    call_kwargs = {}
    if precision is not _MISSING:
        call_kwargs["precision"] = precision
    if unique is not _MISSING:
        call_kwargs["unique"] = unique
    if fractional is not _MISSING:
        call_kwargs["fractional"] = fractional
    if trim is not _MISSING:
        call_kwargs["trim"] = trim
    if sign is not _MISSING:
        call_kwargs["sign"] = sign
    if pad_left is not _MISSING:
        call_kwargs["pad_left"] = pad_left
    if pad_right is not _MISSING:
        call_kwargs["pad_right"] = pad_right
    if min_digits is not _MISSING:
        call_kwargs["min_digits"] = min_digits
    result = numpy.format_float_positional(*args_list, **call_kwargs)
    return _serialize(result)

def fromregex(file, regexp, dtype, encoding=_MISSING):
    """Wrapper for numpy.fromregex with type conversion."""
    args_list = [file, regexp, dtype]
    call_kwargs = {}
    if encoding is not _MISSING:
        call_kwargs["encoding"] = encoding
    result = numpy.fromregex(*args_list, **call_kwargs)
    return _serialize(result)

def indices(dimensions, dtype=_MISSING, sparse=_MISSING):
    """Wrapper for numpy.indices with type conversion."""
    args_list = [dimensions]
    call_kwargs = {}
    if dtype is not _MISSING:
        call_kwargs["dtype"] = dtype
    if sparse is not _MISSING:
        call_kwargs["sparse"] = sparse
    result = numpy.indices(*args_list, **call_kwargs)
    return _serialize(result)

def typename(char):
    """Wrapper for numpy.typename with type conversion."""
    args_list = [char]
    call_kwargs = {}
    result = numpy.typename(*args_list, **call_kwargs)
    return _serialize(result)

def seterr(all=_MISSING, divide=_MISSING, over=_MISSING, under=_MISSING, invalid=_MISSING):
    """Wrapper for numpy.seterr with type conversion."""
    args_list = []
    call_kwargs = {}
    if all is not _MISSING:
        call_kwargs["all"] = all
    if divide is not _MISSING:
        call_kwargs["divide"] = divide
    if over is not _MISSING:
        call_kwargs["over"] = over
    if under is not _MISSING:
        call_kwargs["under"] = under
    if invalid is not _MISSING:
        call_kwargs["invalid"] = invalid
    result = numpy.seterr(*args_list, **call_kwargs)
    return _serialize(result)

def set_printoptions(precision=_MISSING, threshold=_MISSING, edgeitems=_MISSING, linewidth=_MISSING, suppress=_MISSING, nanstr=_MISSING, infstr=_MISSING, formatter=_MISSING, sign=_MISSING, floatmode=_MISSING, *, legacy=_MISSING, override_repr=_MISSING):
    """Wrapper for numpy.set_printoptions with type conversion."""
    args_list = []
    call_kwargs = {}
    if precision is not _MISSING:
        call_kwargs["precision"] = precision
    if threshold is not _MISSING:
        call_kwargs["threshold"] = threshold
    if edgeitems is not _MISSING:
        call_kwargs["edgeitems"] = edgeitems
    if linewidth is not _MISSING:
        call_kwargs["linewidth"] = linewidth
    if suppress is not _MISSING:
        call_kwargs["suppress"] = suppress
    if nanstr is not _MISSING:
        call_kwargs["nanstr"] = nanstr
    if infstr is not _MISSING:
        call_kwargs["infstr"] = infstr
    if formatter is not _MISSING:
        call_kwargs["formatter"] = formatter
    if sign is not _MISSING:
        call_kwargs["sign"] = sign
    if floatmode is not _MISSING:
        call_kwargs["floatmode"] = floatmode
    if legacy is not _MISSING:
        call_kwargs["legacy"] = legacy
    if override_repr is not _MISSING:
        call_kwargs["override_repr"] = override_repr
    result = numpy.set_printoptions(*args_list, **call_kwargs)
    return _serialize(result)

def tri(N, M=_MISSING, k=_MISSING, dtype=_MISSING, *, like=_MISSING):
    """Wrapper for numpy.tri with type conversion."""
    args_list = [N]
    call_kwargs = {}
    if M is not _MISSING:
        call_kwargs["M"] = M
    if k is not _MISSING:
        call_kwargs["k"] = k
    if dtype is not _MISSING:
        call_kwargs["dtype"] = dtype
    if like is not _MISSING:
        call_kwargs["like"] = like
    result = numpy.tri(*args_list, **call_kwargs)
    return _serialize(result)

def printoptions(*args, **kwargs):
    """Wrapper for numpy.printoptions with type conversion."""
    args_list = []
    call_kwargs = {}
    result = numpy.printoptions(*args_list, *args, **call_kwargs, **kwargs)
    return _serialize(result)

def hamming(M):
    """Wrapper for numpy.hamming with type conversion."""
    args_list = [M]
    call_kwargs = {}
    result = numpy.hamming(*args_list, **call_kwargs)
    return _serialize(result)

def diag_indices(n, ndim=_MISSING):
    """Wrapper for numpy.diag_indices with type conversion."""
    args_list = [n]
    call_kwargs = {}
    if ndim is not _MISSING:
        call_kwargs["ndim"] = ndim
    result = numpy.diag_indices(*args_list, **call_kwargs)
    return _serialize(result)

def genfromtxt(fname, dtype=_MISSING, comments=_MISSING, delimiter=_MISSING, skip_header=_MISSING, skip_footer=_MISSING, converters=_MISSING, missing_values=_MISSING, filling_values=_MISSING, usecols=_MISSING, names=_MISSING, excludelist=_MISSING, deletechars=_MISSING, replace_space=_MISSING, autostrip=_MISSING, case_sensitive=_MISSING, defaultfmt=_MISSING, unpack=_MISSING, usemask=_MISSING, loose=_MISSING, invalid_raise=_MISSING, max_rows=_MISSING, encoding=_MISSING, *, ndmin=_MISSING, like=_MISSING):
    """Wrapper for numpy.genfromtxt with type conversion."""
    args_list = [fname]
    call_kwargs = {}
    if dtype is not _MISSING:
        call_kwargs["dtype"] = dtype
    if comments is not _MISSING:
        call_kwargs["comments"] = comments
    if delimiter is not _MISSING:
        call_kwargs["delimiter"] = delimiter
    if skip_header is not _MISSING:
        call_kwargs["skip_header"] = skip_header
    if skip_footer is not _MISSING:
        call_kwargs["skip_footer"] = skip_footer
    if converters is not _MISSING:
        call_kwargs["converters"] = converters
    if missing_values is not _MISSING:
        call_kwargs["missing_values"] = missing_values
    if filling_values is not _MISSING:
        call_kwargs["filling_values"] = filling_values
    if usecols is not _MISSING:
        call_kwargs["usecols"] = usecols
    if names is not _MISSING:
        call_kwargs["names"] = names
    if excludelist is not _MISSING:
        call_kwargs["excludelist"] = excludelist
    if deletechars is not _MISSING:
        call_kwargs["deletechars"] = deletechars
    if replace_space is not _MISSING:
        call_kwargs["replace_space"] = replace_space
    if autostrip is not _MISSING:
        call_kwargs["autostrip"] = autostrip
    if case_sensitive is not _MISSING:
        call_kwargs["case_sensitive"] = case_sensitive
    if defaultfmt is not _MISSING:
        call_kwargs["defaultfmt"] = defaultfmt
    if unpack is not _MISSING:
        call_kwargs["unpack"] = unpack
    if usemask is not _MISSING:
        call_kwargs["usemask"] = usemask
    if loose is not _MISSING:
        call_kwargs["loose"] = loose
    if invalid_raise is not _MISSING:
        call_kwargs["invalid_raise"] = invalid_raise
    if max_rows is not _MISSING:
        call_kwargs["max_rows"] = max_rows
    if encoding is not _MISSING:
        call_kwargs["encoding"] = encoding
    if ndmin is not _MISSING:
        call_kwargs["ndmin"] = ndmin
    if like is not _MISSING:
        call_kwargs["like"] = like
    result = numpy.genfromtxt(*args_list, **call_kwargs)
    return _serialize(result)

def eye(N, M=_MISSING, k=_MISSING, dtype=_MISSING, order=_MISSING, *, device=_MISSING, like=_MISSING):
    """Wrapper for numpy.eye with type conversion."""
    args_list = [N]
    call_kwargs = {}
    if M is not _MISSING:
        call_kwargs["M"] = M
    if k is not _MISSING:
        call_kwargs["k"] = k
    if dtype is not _MISSING:
        call_kwargs["dtype"] = dtype
    if order is not _MISSING:
        call_kwargs["order"] = order
    if device is not _MISSING:
        call_kwargs["device"] = device
    if like is not _MISSING:
        call_kwargs["like"] = like
    result = numpy.eye(*args_list, **call_kwargs)
    return _serialize(result)

def bartlett(M):
    """Wrapper for numpy.bartlett with type conversion."""
    args_list = [M]
    call_kwargs = {}
    result = numpy.bartlett(*args_list, **call_kwargs)
    return _serialize(result)

def blackman(M):
    """Wrapper for numpy.blackman with type conversion."""
    args_list = [M]
    call_kwargs = {}
    result = numpy.blackman(*args_list, **call_kwargs)
    return _serialize(result)

def get_include():
    """Wrapper for numpy.get_include with type conversion."""
    args_list = []
    call_kwargs = {}
    result = numpy.get_include(*args_list, **call_kwargs)
    return _serialize(result)

def fromfunction(function, shape, *, dtype=_MISSING, like=_MISSING, **kwargs):
    """Wrapper for numpy.fromfunction with type conversion."""
    args_list = [function, shape]
    call_kwargs = {}
    if dtype is not _MISSING:
        call_kwargs["dtype"] = dtype
    if like is not _MISSING:
        call_kwargs["like"] = like
    result = numpy.fromfunction(*args_list, **call_kwargs, **kwargs)
    return _serialize(result)
