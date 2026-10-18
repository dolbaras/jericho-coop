"""Decompress Jericho .lc files (u32 header, meaning unknown, + zlib stream of Lua 5.1 bytecode) to .luac."""
import os, struct, sys, zlib

ok = bad = 0
for root, _, files in os.walk(sys.argv[1]):
    for fn in files:
        if not fn.endswith('.lc'):
            continue
        p = os.path.join(root, fn)
        data = open(p, 'rb').read()
        try:
            raw = zlib.decompress(data[4:])
        except Exception as e:
            bad += 1
            print('FAIL', p, e)
            continue
        open(p[:-3] + '.luac', 'wb').write(raw)
        ok += 1
print(f'{ok} ok, {bad} failed')
