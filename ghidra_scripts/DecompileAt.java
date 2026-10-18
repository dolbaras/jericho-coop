// Decompile the functions containing the given addresses and write C to an output file.
// Headless args: <out_file> <hex_addr> [<hex_addr> ...]
// If no function exists at an address, one is created at the nearest preceding
// function start found by Ghidra, or at the address itself.
// @category Jericho

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;

import java.io.FileWriter;
import java.io.PrintWriter;
import java.util.LinkedHashSet;
import java.util.Set;

public class DecompileAt extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);
        Set<Function> done = new LinkedHashSet<>();
        try (PrintWriter out = new PrintWriter(new FileWriter(args[0]))) {
            for (int i = 1; i < args.length; i++) {
                Address a = toAddr(Long.parseLong(args[i].replace("0x", ""), 16));
                Function f = getFunctionContaining(a);
                if (f == null) {
                    out.printf("// %s: no function contains this address%n%n", a);
                    continue;
                }
                if (!done.add(f)) {
                    out.printf("// %s: inside %s (already printed)%n%n", a, f.getName());
                    continue;
                }
                DecompileResults r = decomp.decompileFunction(f, 120, monitor);
                out.printf("// ===== %s in %s @ %s =====%n", a, f.getName(), f.getEntryPoint());
                out.println(r.decompileCompleted() ? r.getDecompiledFunction().getC() : "// decompile failed: " + r.getErrorMessage());
                out.println();
            }
        } finally {
            decomp.dispose();
        }
    }
}
