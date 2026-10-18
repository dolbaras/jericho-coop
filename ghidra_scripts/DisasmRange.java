// Print the disassembly of an address range, disassembling undefined bytes on the fly
// (read-only: changes are not saved with -readOnly).
// Headless args: <out_file> <hex_start> <hex_end>
// @category Jericho

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Instruction;

import java.io.FileWriter;
import java.io.PrintWriter;

public class DisasmRange extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        Address a = toAddr(Long.parseLong(args[1].replace("0x", ""), 16));
        Address end = toAddr(Long.parseLong(args[2].replace("0x", ""), 16));
        try (PrintWriter out = new PrintWriter(new FileWriter(args[0]))) {
            while (a.compareTo(end) < 0) {
                Instruction ins = getInstructionAt(a);
                if (ins == null) {
                    disassemble(a);
                    ins = getInstructionAt(a);
                }
                if (ins == null) { out.printf("%s  db %02x%n", a, getByte(a) & 0xff); a = a.add(1); continue; }
                out.printf("%s  %s%n", a, ins);
                a = a.add(ins.getLength());
            }
        }
    }
}
