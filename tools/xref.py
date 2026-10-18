"""Find code that references a string in Jericho.exe and disassemble around it.

Usage: xref.py <exe> "<exact string>" [bytes_before] [bytes_after]
Scans .text for 4-byte immediates equal to the string's virtual address (push/mov imm32).
"""
import struct, sys
import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_32


def main():
    exe, needle = sys.argv[1], sys.argv[2].encode('latin-1')
    before = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x60
    after = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0x80
    pe = pefile.PE(exe, fast_load=True)
    base = pe.OPTIONAL_HEADER.ImageBase
    data = pe.__data__
    off = data.find(needle)
    while off != -1 and data[off - 1] != 0:
        off = data.find(needle, off + 1)
    if off == -1:
        sys.exit('string not found')
    va = base + pe.get_rva_from_offset(off)
    print(f'string at file 0x{off:x}, VA 0x{va:08x}')
    text = next(s for s in pe.sections if s.Name.startswith(b'.text'))
    code = text.get_data()
    tva = base + text.VirtualAddress
    md = Cs(CS_ARCH_X86, CS_MODE_32)
    pat = struct.pack('<I', va)
    i = code.find(pat)
    while i != -1:
        start = max(0, i - before)
        print(f'\n--- ref at 0x{tva + i:08x}')
        for ins in md.disasm(code[start:i + after], tva + start):
            mark = '>>' if ins.address <= tva + i < ins.address + ins.size else '  '
            print(f'{mark} {ins.address:08x}  {ins.mnemonic:6} {ins.op_str}')
        i = code.find(pat, i + 1)


if __name__ == '__main__':
    main()
