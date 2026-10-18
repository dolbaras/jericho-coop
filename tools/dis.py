"""Disassemble a VA range of Jericho.exe with import names and string comments.
Usage: dis.py <exe> <start_hex> <end_hex>"""
import re, sys
import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

pe = pefile.PE(sys.argv[1])
B = pe.OPTIONAL_HEADER.ImageBase
d = pe.__data__
imp = {i.address: (i.name.decode() if i.name else str(i.ordinal))
       for e in pe.DIRECTORY_ENTRY_IMPORT for i in e.imports}
md = Cs(CS_ARCH_X86, CS_MODE_32)


def cstr(va):
    try:
        o = pe.get_offset_from_rva(va - B)
    except Exception:
        return None
    s = d[o:o + 70].split(b'\0')[0]
    if len(s) > 2 and all(32 <= c < 127 or c in (9, 10) for c in s):
        return s.decode('latin-1').replace('\n', '\n')
    return None


start, end = int(sys.argv[2], 16), int(sys.argv[3], 16)
o = pe.get_offset_from_rva(start - B)
for ins in md.disasm(d[o:o + (end - start)], start):
    extra = ''
    for tok in re.findall(r'0x[0-9a-f]+', ins.op_str):
        v = int(tok, 16)
        if v in imp:
            extra += '  ; ' + imp[v]
        s = cstr(v) if 0x6f0000 < v < 0x7c0000 else None
        if s:
            extra += f'  ; "{s[:60]}"'
    print(f'{ins.address:08x} {ins.mnemonic:6} {ins.op_str}{extra}')
