// Print the disassembly of the functions containing the given addresses.
// Headless args: <out_file> <hex_addr> [<hex_addr> ...]
// @category Jericho

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;

import java.io.FileWriter;
import java.io.PrintWriter;

public class DisasmAt extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        try (PrintWriter out = new PrintWriter(new FileWriter(args[0]))) {
            for (int i = 1; i < args.length; i++) {
                Address a = toAddr(Long.parseLong(args[i].replace("0x", ""), 16));
                Function f = getFunctionContaining(a);
                if (f == null) { out.printf("// %s: no function%n", a); continue; }
                out.printf("// ===== %s @ %s =====%n", f.getName(), f.getEntryPoint());
                for (Instruction ins : currentProgram.getListing().getInstructions(f.getBody(), true)) {
                    out.printf("%s  %s%n", ins.getAddress(), ins);
                }
                out.println();
            }
        }
    }
}
