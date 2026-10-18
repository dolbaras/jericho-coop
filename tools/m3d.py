"""Readers/writers for Clive Barker's Jericho (ScrapEngine) M3D binaries.

* SM3: static scene/model (node hierarchy + meshes).
* CM3: animation ("compiled" M3D): an SCN chunk without nodes plus an ANI chunk.

Layout reverse engineered from the files and from Jericho.exe
(lee_M3D.cpp, Escena.cpp, Animacion.cpp). See mod/docs/cm3-format.md.

Everything is little endian. Chunks are a 4-byte tag ("ANI\\0") followed by a
u32 that is 0 for plain chunks and the payload size for sized chunks (only
NABK is sized). Strings are u32 length (including the NUL) + bytes + NUL; an
empty string is a single u32 0.
"""
import re, struct

M3D_VERSION = 0x65226E

# per-track channel flags, in serialisation order, with element size in bytes
CHANNELS = ((0x01, 12, 'pos'),     # float x, y, z
            (0x02, 16, 'rot'),     # float quaternion (4)
            (0x04, 4, 'f04'),      # float
            (0x08, 4, 'f08'),      # float
            (0x10, 4, 'f10'),      # float
            (0x80, 1, 'b80'))      # byte (visibility?)
FLAG_EVA = 0x1000                  # per-vertex animation, EVA sub-chunk in NAM
CM3_SUPPORTED = 0x109F


class FormatError(ValueError):
    pass


# --------------------------------------------------------------- primitives

class Reader:
    def __init__(self, data, pos=0):
        self.d = data
        self.p = pos

    def u32(self):
        if self.p + 4 > len(self.d):
            raise FormatError(f'EOF at {self.p:#x}')
        v = struct.unpack_from('<I', self.d, self.p)[0]
        self.p += 4
        return v

    def f32(self):
        v = struct.unpack_from('<f', self.d, self.p)[0]
        self.p += 4
        return v

    def raw(self, n):
        if n < 0 or self.p + n > len(self.d):
            raise FormatError(f'EOF reading {n} bytes at {self.p:#x}')
        v = self.d[self.p:self.p + n]
        self.p += n
        return v

    def tag(self, expect):
        t = self.raw(4)
        if t != expect:
            raise FormatError(f'expected {expect!r} at {self.p - 4:#x}, got {t!r}')

    def string(self):
        n = self.u32()
        if n == 0:
            return ''
        s = self.raw(n)
        if s[-1:] != b'\0':
            raise FormatError(f'unterminated string at {self.p - n:#x}')
        return s[:-1].decode('latin-1')

    def ini(self):
        """Serialized FileINI object: u32 present; INI chunk {u32 1, u32 n, n strings}."""
        if not self.u32():
            return None
        self.tag(b'INI\0')
        if self.u32() != 0 or self.u32() != 1:
            raise FormatError(f'bad INI chunk at {self.p:#x}')
        return [self.string() for _ in range(self.u32())]


def p_u32(*v):
    return struct.pack(f'<{len(v)}I', *v)


def p_string(s):
    if not s:
        return p_u32(0)
    b = s.encode('latin-1') + b'\0'
    return p_u32(len(b)) + b


def p_ini(lines):
    if lines is None:
        return p_u32(0)
    return p_u32(1) + b'INI\0' + p_u32(0, 1, len(lines)) + b''.join(p_string(s) for s in lines)


# --------------------------------------------------------------------- SM3

def _try_node(d, p, maxname=512):
    """Try to read a node record at p. Returns dict or None."""
    try:
        r = Reader(d, p)
        pre = r.raw(24)
        name = r.string()
        if not name or len(name) > maxname or not _printable(name):
            return None
        parent = r.string()
        if len(parent) > maxname or not _printable(parent):
            return None
        fixed = r.raw(188)
        ini = r.ini()
        has_obj = r.u32()
        if has_obj > 1:
            return None
        return dict(off=p, name=name, parent=parent, ini=ini, has_obj=has_obj,
                    pre=pre, fixed=fixed, end=r.p)
    except (FormatError, struct.error, UnicodeError):
        return None


def _printable(s):
    return all(c >= ' ' or c in '\t\r\n' for c in s)


def read_header(d):
    r = Reader(d)
    magic = r.raw(4)
    if magic not in (b'CM3\0', b'SM3\0'):
        raise FormatError(f'not an SM3/CM3 file: {magic!r}')
    r.u32()
    ver = r.u32()
    nh = 3 if magic == b'CM3\0' else 2
    hashes = [r.u32() for _ in range(nh)]
    return magic, ver, hashes, r.p


def sm3_nodes(d):
    """Return the scene node list of a decompressed SM3, in file (= engine) order.

    Object payloads (meshes etc.) are not parsed; after a node with an object
    the next node record is located by scanning for a record whose parent is
    an already-seen node. The result is checked against the node count
    stored in the SCN chunk.
    """
    magic, ver, hashes, p = read_header(d)
    r = Reader(d, p)
    r.tag(b'SCN\0')
    r.u32(); r.u32()
    r.string(); r.string(); r.ini()
    r.raw(8 + 8 + 24 + 12 + 4)
    r.ini()
    nmat = r.u32()
    # materials are not parsed: search for "u32 1, u32 count, first node record"
    start = r.p
    first = None
    for m in re.finditer(rb'\x01\x00\x00\x00', d[start:]):
        q = start + m.start()
        cnt = struct.unpack_from('<I', d, q + 4)[0]
        if 0 < cnt < 100000:
            n = _try_node(d, q + 8)
            if n and n['parent'] == '':
                first, count = n, cnt
                break
    if first is None:
        raise FormatError('node list not found')
    nodes = [first]
    q = first['end']
    names = {first['name']}
    while len(nodes) < count:
        if not nodes[-1]['has_obj']:
            n = _try_node(d, q)
            if not n:
                raise FormatError(f'bad node record at {q:#x} after {nodes[-1]["name"]!r}')
        else:
            q += 4  # object type
            while True:
                n = _try_node(d, q)
                if n and (n['parent'] in names):
                    break
                q += 1
                if q >= len(d):
                    raise FormatError(f'EOF looking for the node after {nodes[-1]["name"]!r}')
        nodes.append(n)
        names.add(n['name'])
        q = n['end']
    for i, n in enumerate(nodes):
        n['index'] = i
    return dict(magic=magic, version=ver, hashes=hashes, materials=nmat,
                count=count, nodes=nodes)


def sm3_renames(d):
    """[RenameNodes] section of the model's SCN FileINI: {old: new}."""
    magic, ver, hashes, p = read_header(d)
    r = Reader(d, p)
    r.tag(b'SCN\0')
    r.u32(); r.u32()
    r.string(); r.string()
    lines = r.ini() or []
    out, sect = {}, None
    for ln in lines:
        s = ln.strip()
        if s.startswith('['):
            sect = s.lower()
        elif sect == '[renamenodes]' and '=' in s and not s.startswith(';'):
            a, b = s.split('=', 1)
            out[a.strip()] = b.strip()
    return out


# --------------------------------------------------------------------- CM3

class Track:
    """One AnimNodo: channels for one scene node.

    primer: first frame, nframes: frames stored, flags: channel bits present,
    opt: per channel 'optimized' (constant: 1 element instead of nframes),
    stm: per channel 'stream' (opt & stm & flag -> compressed stream whose
    byte size is stored in NAM), data: {flag: raw bytes incl. padding},
    stream_size: {flag: u32 size from NAM}, eva: raw EVA chunk bytes or None.
    """
    __slots__ = ('primer', 'nframes', 'flags', 'opt', 'stm', 'data', 'stream_size', 'eva',
                 'nam_size_field')

    def __init__(self):
        self.data = {}
        self.stream_size = {}
        self.eva = None
        self.nam_size_field = 0

    def channel_bytes(self, flag, elt):
        """Bytes this channel occupies in NABK (with 4-byte padding)."""
        cnt = 1 if flag & self.opt else self.nframes
        if flag & self.opt & self.stm:
            size = self.stream_size[flag]
        else:
            size = elt
        return (cnt * size + 3) & ~3

    def kind(self, flag):
        if not self.flags & flag:
            return None
        if flag & self.opt & self.stm:
            return 'stream'
        if flag & self.opt:
            return 'const'
        return 'frames'

    def nabk(self):
        return b''.join(self.data[f] for f, _, _ in CHANNELS if self.flags & f)

    def nam(self):
        out = [b'NAM\0', p_u32(self.nam_size_field, 1, self.primer, self.nframes,
                               self.flags, self.opt, self.stm)]
        for f, _, _ in CHANNELS:
            if self.flags & f and f & self.opt & self.stm:
                out.append(p_u32(self.stream_size[f]))
        if self.flags & FLAG_EVA:
            out.append(self.eva)
        return b''.join(out)

    # ---- decoding helpers (only for uncompressed channels)
    def values(self, flag):
        """Decoded per-frame values for 'const'/'frames' channels, else None."""
        k = self.kind(flag)
        if k not in ('const', 'frames'):
            return None
        elt = {f: e for f, e, _ in CHANNELS}[flag]
        n = 1 if k == 'const' else self.nframes
        raw = self.data[flag]
        if flag == 0x80:
            return list(raw[:n])
        fmt = '<%df' % (elt // 4)
        return [struct.unpack_from(fmt, raw, i * elt) for i in range(n)]

    def copy(self):
        t = Track()
        for s in self.__slots__:
            v = getattr(self, s)
            setattr(t, s, dict(v) if isinstance(v, dict) else v)
        return t


def _skip_eva(d, p):
    """EVA chunk: 'EVA\\0', u32 0, u32 1, u32 n, then n vertex-anim records.

    The record layout is not known (no shipped CM3 uses it as far as checked);
    raise so that such files are reported rather than mis-parsed.
    """
    raise FormatError(f'EVA (vertex animation) chunk at {p:#x} not supported')


class CM3:
    """A parsed CM3 file.

    head: bytes before ANI (CM3 header + SCN chunk start, kept verbatim)
    ani_*: ANI header fields; tracks: list of Track; tail: bytes after the
    last NAM (expected empty).
    """

    def __init__(self, data):
        self.parse(data)

    def parse(self, d):
        magic, ver, hashes, p = read_header(d)
        if magic != b'CM3\0':
            raise FormatError('not a CM3 file')
        self.version, self.hashes = ver, hashes
        r = Reader(d, p)
        r.tag(b'SCN\0')
        self.scn_size_field = r.u32()
        if r.u32() != 1:
            raise FormatError('SCN version != 1')
        self.scn_strings = [r.string(), r.string()]
        self.scn_ini = r.ini()
        self.scn_fixed = r.raw(8 + 8 + 24 + 12 + 4)
        self.scn_ini2 = r.ini()
        nmat = r.u32()
        if nmat:
            raise FormatError(f'CM3 with {nmat} materials not supported')
        if r.u32() != 1:
            raise FormatError('expected u32 1 before node count')
        nnodes = r.u32()
        if nnodes:
            raise FormatError(f'CM3 with {nnodes} scene nodes not supported')
        has_anim = r.u32()
        if has_anim != 1:
            raise FormatError('CM3 without ANI')
        self.head = d[:r.p]
        # ---- ANI
        r.tag(b'ANI\0')
        self.ani_size_field = r.u32()
        if r.u32() != 4:
            raise FormatError('ANI version != 4')
        self.fps = r.raw(4)                       # float
        self.ani_0c = r.u32()                     # unknown (always 0 so far)
        self.frames = r.u32()                     # animation length in frames
        ntracks = r.u32()
        self.ani_bool = r.u32()                   # bool at Animacion+0x14
        self.ani_vec = r.raw(12)                  # 3 floats at Animacion+0x18
        n = r.u32()
        self.ani_blob = r.raw(n)                  # u32-sized blob at Animacion+0x28
        r.tag(b'NABK')
        size = r.u32()
        nabk = r.raw(size)
        # ---- NAM per track
        self.tracks = []
        for i in range(ntracks):
            t = Track()
            r.tag(b'NAM\0')
            t.nam_size_field = r.u32()
            if r.u32() != 1:
                raise FormatError(f'NAM {i}: version != 1')
            t.primer, t.nframes, t.flags, t.opt, t.stm = (r.u32() for _ in range(5))
            if t.flags & ~CM3_SUPPORTED or t.opt & ~7 or t.stm & ~7:
                raise FormatError(f'NAM {i}: unsupported flags {t.flags:#x}/{t.opt:#x}/{t.stm:#x}')
            for f, _, _ in CHANNELS:
                if t.flags & f and f & t.opt & t.stm:
                    t.stream_size[f] = r.u32()
            if t.flags & FLAG_EVA:
                _skip_eva(d, r.p)
            self.tracks.append(t)
        self.tail = d[r.p:]
        # ---- split NABK by track
        q = 0
        for i, t in enumerate(self.tracks):
            for f, elt, _ in CHANNELS:
                if t.flags & f:
                    n = t.channel_bytes(f, elt)
                    if q + n > len(nabk):
                        raise FormatError(f'track {i}: NABK overrun')
                    t.data[f] = nabk[q:q + n]
                    q += n
                    if f & t.opt & t.stm:
                        # self-describing stream: first u16 = size / 4
                        (w,) = struct.unpack_from('<H', t.data[f], 0)
                        if w * 4 != t.stream_size[f]:
                            raise FormatError(f'track {i}: stream size mismatch')
        if q != len(nabk):
            raise FormatError(f'NABK: {len(nabk) - q} bytes unused')

    def serialize(self):
        nabk = b''.join(t.nabk() for t in self.tracks)
        out = [self.head,
               b'ANI\0', p_u32(self.ani_size_field, 4), self.fps,
               p_u32(self.ani_0c, self.frames, len(self.tracks), self.ani_bool),
               self.ani_vec, p_u32(len(self.ani_blob)), self.ani_blob,
               b'NABK', p_u32(len(nabk)), nabk]
        out.extend(t.nam() for t in self.tracks)
        out.append(self.tail)
        return b''.join(out)

    @property
    def fps_value(self):
        return struct.unpack('<f', self.fps)[0]
