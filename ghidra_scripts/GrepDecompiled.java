// Decompile functions whose instructions use ALL of the given scalar displacements/immediates,
// and print those whose C output matches a regex.
// Headless args: <out_file> <regex> <hex_scalar> [<hex_scalar> ...]
// Example: out.c "\+ 0x28\) \+" 0x28 0x24
// @category Jericho

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.scalar.Scalar;

import java.io.FileWriter;
import java.io.PrintWriter;
import java.util.HashSet;
import java.util.Set;
import java.util.regex.Pattern;

public class GrepDecompiled extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        Pattern re = Pattern.compile(args[1]);
        Set<Long> want = new HashSet<>();
        for (int i = 2; i < args.length; i++) want.add(Long.parseLong(args[i].replace("0x", ""), 16));
        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);
        int cand = 0, hits = 0;
        try (PrintWriter out = new PrintWriter(new FileWriter(args[0]))) {
            for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
                if (monitor.isCancelled()) break;
                Set<Long> seen = new HashSet<>();
                for (Instruction ins : currentProgram.getListing().getInstructions(f.getBody(), true)) {
                    for (int op = 0; op < ins.getNumOperands(); op++) {
                        for (Object o : ins.getOpObjects(op)) {
                            if (o instanceof Scalar) seen.add(((Scalar) o).getUnsignedValue());
                        }
                    }
                }
                if (!seen.containsAll(want)) continue;
                cand++;
                DecompileResults r = decomp.decompileFunction(f, 60, monitor);
                if (!r.decompileCompleted()) continue;
                String c = r.getDecompiledFunction().getC();
                if (!re.matcher(c).find()) continue;
                hits++;
                out.printf("// ===== %s @ %s =====%n", f.getName(), f.getEntryPoint());
                out.println(c);
                out.println();
            }
            out.printf("// candidates %d, hits %d%n", cand, hits);
        } finally {
            decomp.dispose();
        }
    }
}
