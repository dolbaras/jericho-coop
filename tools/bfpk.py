"""List and extract BFPK (.packed) archives from Clive Barker's Jericho.

Layout (observed): "BFPK", u32 version, u32 count, then count entries of
u32 name_len, name, u32 size, u32 offset (absolute). Data follows the table.
"""
import argparse, collections, fnmatch, os, struct, sys


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('archives', nargs='+')
    ap.add_argument('--list', action='store_true')
    ap.add_argument('--stats', action='store_true')
    ap.add_argument('--extract', metavar='OUT_DIR')
    ap.add_argument('--filter', default='*', help='fnmatch pattern on entry names')
    a = ap.parse_args()
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
        if a.extract:
            with open(arc, 'rb') as f:
                for name, size, offset in entries:
                    parts = [p for p in name.replace('\\', '/').split('/') if p not in ('', '.', '..')]
                    dst = os.path.join(a.extract, *parts)
                    os.makedirs(os.path.dirname(dst), exist_ok=True)
                    f.seek(offset)
                    with open(dst, 'wb') as o:
                        o.write(f.read(size))


if __name__ == '__main__':
    main()
