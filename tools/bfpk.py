"""List, extract and write BFPK (.packed) archives from Clive Barker's Jericho.

Layout (observed): "BFPK", u32 version, u32 count, then count entries of
u32 name_len, name, u32 size, u32 offset (absolute). Data follows the table.

Version 1 archives (Data00..05.packed): every entry is stored as
u32 compressed_size + one zlib stream (zlib level 6, i.e. Python's default,
reproduces the original bytes exactly). The index `size` is the
*uncompressed* size, so reading `size` bytes at `offset` is wrong: the
stored record is 4 + compressed_size bytes.
Version 0 archives (Music.packed): entries are stored raw, `size` bytes.

Extraction writes the stored record (u32 + zlib) by default, as in the
archive; `--decompress` writes the plain file content instead.

Writing: `--create OUT.packed --root DIR [existing archives...]` packs every
file under DIR (plain content, entry name = relative path in lowercase) the
same way as the originals; names already present in the listed archives
are refused. write_archive() does the same from Python.
"""
import argparse, collections, fnmatch, os, struct, sys, zlib


def read_index(path):
    with open(path, 'rb') as f:
        magic, version, count = struct.unpack('<4sII', f.read(12))
        if magic != b'BFPK':
            raise ValueError(f'{path}: not a BFPK archive')
        entries = []
        for _ in range(count):
            (n,) = struct.unpack('<I', f.read(4))
            name = f.read(n).decode('latin-1')
            size, offset = struct.unpack('<II', f.read(8))
            entries.append((name, size, offset))
    return version, entries


def read_stored(f, version, entry):
    """Return the stored bytes of an entry (u32 + zlib for version 1)."""
    name, size, offset = entry
    f.seek(offset)
    if version == 0:
        return f.read(size)
    head = f.read(4)
    (csize,) = struct.unpack('<I', head)
    return head + f.read(csize)


def unpack_stored(version, stored):
    """Stored record -> plain file bytes."""
    if version == 0:
        return stored
    (csize,) = struct.unpack_from('<I', stored, 0)
    return zlib.decompress(stored[4:4 + csize])


def pack_stored(data, version=1):
    """Plain file bytes -> stored record, compressed like the originals."""
    if version == 0:
        return data
    z = zlib.compress(data, 6)
    return struct.pack('<I', len(z)) + z


def read_file(path, version=None):
    """Read a file that is either a stored record (u32 + zlib) or plain."""
    with open(path, 'rb') as f:
        d = f.read()
    if len(d) >= 6 and d[4:5] == b'\x78':
        try:
            return unpack_stored(1, d)
        except zlib.error:
            pass
    return d


def write_archive(path, files, version=1):
    """files: list of (archive_name, plain_bytes). Names use '/' separators.

    Writes the index first, then the stored records in index order, like
    the original archives.
    """
    names = [n.encode('latin-1') for n, _ in files]
    stored = [pack_stored(d, version) for _, d in files]
    table = 12 + sum(4 + len(n) + 8 for n in names)
    out = [struct.pack('<4sII', b'BFPK', version, len(files))]
    off = table
    for n, (_, d), s in zip(names, files, stored):
        out.append(struct.pack('<I', len(n)) + n + struct.pack('<II', len(d), off))
        off += len(s)
    out.extend(stored)
    with open(path, 'wb') as f:
        f.write(b''.join(out))


def create(out, root, version=1, existing=()):
    """Pack every file under root as '<relative path, lowercase, />'.

    Refuses names that already exist in the archives listed in existing
    (the engine keeps the first entry of a name, so a duplicate would be
    ignored or would shadow the original)."""
    taken = set()
    for arc in existing:
        taken.update(e[0].lower() for e in read_index(arc)[1])
    items = []
    for dirpath, _, files in os.walk(root):
        for fn in sorted(files):
            full = os.path.join(dirpath, fn)
            name = os.path.relpath(full, root).replace(os.sep, '/').lower()
            if name in taken:
                raise SystemExit(f'{name} already exists in the game archives')
            with open(full, 'rb') as f:
                items.append((name, f.read()))
    items.sort()
    write_archive(out, items, version)
    return len(items)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('archives', nargs='*')
    ap.add_argument('--create', metavar='OUT', help='write a new archive from the files under --root')
    ap.add_argument('--root', help='with --create: folder whose relative paths become entry names')
    ap.add_argument('--raw', action='store_true', help='with --create: version 0 (uncompressed) archive')
    ap.add_argument('--list', action='store_true')
    ap.add_argument('--stats', action='store_true')
    ap.add_argument('--extract', metavar='OUT_DIR')
    ap.add_argument('--decompress', action='store_true',
                    help='with --extract: write plain file content instead of the stored record')
    ap.add_argument('--verify', action='store_true',
                    help='decompress every selected entry and check its size against the index')
    ap.add_argument('--filter', default='*', help='fnmatch pattern on entry names')
    a = ap.parse_args()
    if a.create:
        if not a.root:
            ap.error('--create needs --root')
        n = create(a.create, a.root, 0 if a.raw else 1, a.archives)
        print(f'# {a.create}: {n} entries', file=sys.stderr)
        return
    for arc in a.archives:
        version, entries = read_index(arc)
        entries = [e for e in entries if fnmatch.fnmatch(e[0].lower(), a.filter.lower())]
        print(f'# {arc}: version {version}, {len(entries)} entries', file=sys.stderr)
        if a.stats:
            c = collections.Counter(os.path.splitext(e[0])[1].lower() for e in entries)
            for ext, k in c.most_common():
                print(f'{k:6d} {ext}')
        if a.list:
            for name, size, offset in entries:
                print(f'{offset:10d} {size:10d} {name}')
        if a.extract or a.verify:
            bad = 0
            with open(arc, 'rb') as f:
                for e in entries:
                    name = e[0]
                    s = read_stored(f, version, e)
                    if a.verify or a.decompress:
                        plain = unpack_stored(version, s)
                        if len(plain) != e[1]:
                            bad += 1
                            print(f'size mismatch: {name} {len(plain)} != {e[1]}', file=sys.stderr)
                    if a.extract:
                        parts = [p for p in name.replace('\\', '/').split('/') if p not in ('', '.', '..')]
                        dst = os.path.join(a.extract, *parts)
                        os.makedirs(os.path.dirname(dst), exist_ok=True)
                        with open(dst, 'wb') as o:
                            o.write(plain if a.decompress else s)
            if a.verify:
                print(f'# verify: {len(entries) - bad} ok, {bad} bad', file=sys.stderr)


if __name__ == '__main__':
    main()
