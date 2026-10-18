// Decompile every function that calls (or references) the functions at the given addresses.
// Headless args: <out_file> <hex_addr> [<hex_addr> ...]
// @category Jericho

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;

import java.io.FileWriter;
import java.io.PrintWriter;
import java.util.LinkedHashSet;
import java.util.Set;

public class DecompileCallers extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);
        Set<Function> done = new LinkedHashSet<>();
        try (PrintWriter out = new PrintWriter(new FileWriter(args[0]))) {
            for (int i = 1; i < args.length; i++) {
                Address a = toAddr(Long.parseLong(args[i].replace("0x", ""), 16));
                out.printf("// ##### references to %s%n", a);
                for (Reference r : getReferencesTo(a)) {
                    Function f = getFunctionContaining(r.getFromAddress());
                    if (f == null) {
                        out.printf("//   %s (%s): no function%n", r.getFromAddress(), r.getReferenceType());
                        continue;
                    }
                    out.printf("//   %s in %s%n", r.getFromAddress(), f.getName());
                    if (!done.add(f)) continue;
                    DecompileResults res = decomp.decompileFunction(f, 120, monitor);
                    out.printf("// ===== %s @ %s =====%n", f.getName(), f.getEntryPoint());
                    out.println(res.decompileCompleted() ? res.getDecompiledFunction().getC() : "// decompile failed: " + res.getErrorMessage());
                    out.println();
                }
            }
        } finally {
            decomp.dispose();
        }
    }
}
